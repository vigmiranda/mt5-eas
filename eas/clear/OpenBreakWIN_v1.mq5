//+------------------------------------------------------------------+
//| OpenBreakWIN_v1.mq5                                               |
//| Daytrade WIN (Clear) — Opening Range Breakout                     |
//| Caixa abertura → rompe com volume → 1 posição → BE + trail (máx)  |
//| Sem META DIA 3% | STOP DIA 5% | flat ~11:00 | ScalpWIN pausado   |
//| v1.00                                                             |
//+------------------------------------------------------------------+
#property copyright "Vitor / mt5-eas"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_WIN_SIZING
{
   SIZING_BY_CAPITAL = 0,
   SIZING_FIXED      = 1
};

enum ENUM_CAPITAL_MODE
{
   CAPITAL_VIRTUAL = 0,
   CAPITAL_MANUAL  = 1,
   CAPITAL_BROKER  = 2,
   CAPITAL_AUTO    = 3
};

//------------------------ Inputs ------------------------------------
input group "=== Volume / capital virtual ==="
input ENUM_WIN_SIZING   InpSizingMode        = SIZING_BY_CAPITAL;
input ENUM_CAPITAL_MODE InpCapitalMode       = CAPITAL_VIRTUAL;
input double InpClearSaldo        = 5353.45; // Saldo Clear (alinhar ao atual)
input double InpBandStart          = 500.0;
input double InpBandWidth          = 1000.0;
input double InpFixedVolume        = 1.0;
input double InpMaxVolume          = 10.0;
input double InpMinCapitalTrade    = 500.0;
input double InpBrokerMinReliable  = 50.0;
input bool   InpIncludeFloating    = true;
input bool   InpEstimateFees       = true;
input double InpFeePerSide         = 0.25;
input bool   InpResetVirtualSeed   = false;
input bool   InpSaveDayHistory     = true;
input string InpHistoryFile        = "OpenBreakWIN_v1_equity.csv";

input group "=== Risco diário ==="
input double InpStopDiaPct         = 5.0;     // STOP DIA %
input bool   InpFlatOnDailyLoss    = true;
input int    InpMaxTradesDay       = 1;       // ORB clássico: 1 entrada/dia
input int    InpMaxPositions       = 1;
input int    InpMaxSpreadPoints    = 40;

input group "=== Opening Range (horário servidor MT5 / BRT Clear) ==="
input int    InpBoxStartH          = 9;
input int    InpBoxStartM          = 0;       // Início do caixote
input int    InpBoxEndH            = 9;
input int    InpBoxEndM            = 15;      // Fim do caixote (15 min)
input int    InpEntryEndH          = 10;
input int    InpEntryEndM          = 30;      // Após isso: sem novas entradas
input int    InpFlatH              = 11;
input int    InpFlatM              = 0;       // Flat forçado (fim da janela manhã)

input group "=== Rompimento ==="
input ENUM_TIMEFRAMES InpTF        = PERIOD_M5;
input int    InpBreakBufferPts     = 20;      // Buffer além da caixa (pontos)
input bool   InpUseVolumeFilter    = true;
input int    InpVolAvgBars         = 20;
input double InpVolMinX            = 1.00;    // Volume do candle >= média × X
input double InpMinBoxPts          = 80.0;    // Caixa mínima (evita range morto)
input double InpMaxBoxPts          = 1200.0;  // Caixa máxima (evita gap/explosão)

input group "=== Stop / BE / Trail (busca máximo da pernada) ==="
input bool   InpSLBeyondBox        = true;    // SL do outro lado da caixa
input double InpSL_ATR_Mult        = 1.20;    // Fallback / folga extra se caixa estreita
input int    InpATRPeriod          = 14;
input int    InpMinSL_Points       = 120;
input int    InpMaxSL_Points       = 800;
input double InpMaxSL_CapitalPct   = 5.0;
input int    InpBE_Points          = 150;     // Move SL p/ BE após X pts de lucro
input int    InpBE_LockPoints      = 20;      // Trava BE + estes pts
input double InpTrailStart_ATR     = 0.80;    // Após X ATR de lucro, trail ativo
input double InpTrail_ATR          = 0.50;    // Distância do trail

input group "=== Geral ==="
input long   InpMagic              = 260918;  // Único (ScalpWIN=260917)
input int    InpSlippagePoints     = 30;
input string InpTradeComment       = "OpenBreakWIN_v1";
input bool   InpVerboseLog         = true;

//------------------------ Estado ------------------------------------
datetime g_dayStart = 0;
double   g_dayStartEquity = 0.0;
datetime g_lastBarTime = 0;
bool     g_dayStopped = false;
bool     g_loggedDailyFlat = false;
int      g_tradesToday = 0;
string   g_capitalSource = "n/a";
string   g_lastSkipReason = "";

double   g_seedCapital = 0.0;
double   g_realizedAll = 0.0;
double   g_feesAll = 0.0;
datetime g_equityEpoch = 0;

// Opening range do dia
double   g_boxHigh = 0.0;
double   g_boxLow  = 0.0;
bool     g_boxReady = false;
bool     g_boxLogged = false;
bool     g_beDone = false;

int hATR = INVALID_HANDLE;
int hVol = INVALID_HANDLE;

//+------------------------------------------------------------------+
double ClampVolume(const double v)
{
   double vol = MathMax(0.0, v);
   vol = MathMin(vol, InpMaxVolume);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 1.0;
   vol = MathFloor(vol / step + 1e-8) * step;
   if(vol < vmin) vol = 0.0;
   if(vol > vmax) vol = vmax;
   return vol;
}

//+------------------------------------------------------------------+
int CurrentSpreadPoints()
{
   long spr = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spr > 0) return (int)spr;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0 || _Point <= 0.0) return 0;
   return (int)MathRound((ask - bid) / _Point);
}

//+------------------------------------------------------------------+
int MinStopDistancePoints()
{
   int stops = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   int need = MathMax(stops, freeze);
   if(need < 1) need = 1;
   return need;
}

//+------------------------------------------------------------------+
bool IsWinSymbol()
{
   string s = _Symbol;
   StringToUpper(s);
   return (StringFind(s, "WIN") >= 0);
}

//+------------------------------------------------------------------+
int MinutesOfDay(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.hour * 60 + dt.min;
}

//+------------------------------------------------------------------+
int HM(const int h, const int m) { return h * 60 + m; }

//+------------------------------------------------------------------+
bool InBoxBuildWindow(const datetime t)
{
   int now = MinutesOfDay(t);
   return (now >= HM(InpBoxStartH, InpBoxStartM) && now < HM(InpBoxEndH, InpBoxEndM));
}

//+------------------------------------------------------------------+
bool BoxShouldBeReady(const datetime t)
{
   return (MinutesOfDay(t) >= HM(InpBoxEndH, InpBoxEndM));
}

//+------------------------------------------------------------------+
bool EntryWindowOpen(const datetime t)
{
   int now = MinutesOfDay(t);
   return (now >= HM(InpBoxEndH, InpBoxEndM) && now < HM(InpEntryEndH, InpEntryEndM));
}

//+------------------------------------------------------------------+
bool ShouldFlat(const datetime t)
{
   return (MinutesOfDay(t) >= HM(InpFlatH, InpFlatM));
}

//+------------------------------------------------------------------+
string GVPrefix()
{
   return StringFormat("OpenBreakWIN_v100_%I64d_", InpMagic);
}

//+------------------------------------------------------------------+
void EnsureSeedCapital()
{
   string keySeed = GVPrefix() + "seed";
   string keyEpoch = GVPrefix() + "epoch";

   if(InpResetVirtualSeed || !GlobalVariableCheck(keySeed) || !GlobalVariableCheck(keyEpoch))
   {
      g_seedCapital = InpClearSaldo;
      g_equityEpoch = TimeTradeServer();
      GlobalVariableSet(keySeed, g_seedCapital);
      GlobalVariableSet(keyEpoch, (double)g_equityEpoch);
      PrintFormat("OpenBreak: semente R$%.2f a partir de %s | GV %s",
                  g_seedCapital, TimeToString(g_equityEpoch, TIME_DATE|TIME_MINUTES), keySeed);
   }
   else
   {
      g_seedCapital = GlobalVariableGet(keySeed);
      g_equityEpoch = (datetime)GlobalVariableGet(keyEpoch);
   }
}

//+------------------------------------------------------------------+
double FloatingPnLOurs()
{
   double pnl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

//+------------------------------------------------------------------+
void CalcRealizedAndFeesSinceEpoch(double &pnlOut, double &feesOut)
{
   pnlOut = 0.0;
   feesOut = 0.0;
   EnsureSeedCapital();
   datetime from = g_equityEpoch;
   if(from <= 0) from = 0;
   if(!HistorySelect(from, TimeTradeServer() + 1))
      return;

   double commissionSum = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;

      datetime td = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(td < from) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      double vol = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double comm = HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      if(InpEstimateFees && InpFeePerSide > 0.0 &&
         (entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_OUT ||
          entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY))
         feesOut += InpFeePerSide * MathMax(vol, 1.0);

      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         pnlOut += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP)
                 + comm;
         commissionSum += comm;
      }
   }
   if(InpEstimateFees && MathAbs(commissionSum) >= 0.01)
      feesOut = 0.0;
}

//+------------------------------------------------------------------+
double GetVirtualCapital()
{
   EnsureSeedCapital();
   double pnl, fees;
   CalcRealizedAndFeesSinceEpoch(pnl, fees);
   g_realizedAll = pnl;
   g_feesAll = fees;
   double cap = g_seedCapital + pnl - fees;
   if(InpIncludeFloating)
      cap += FloatingPnLOurs();
   g_capitalSource = "virtual";
   return MathMax(0.0, cap);
}

//+------------------------------------------------------------------+
double BrokerReportedCapital()
{
   return MathMax(AccountInfoDouble(ACCOUNT_EQUITY),
          MathMax(AccountInfoDouble(ACCOUNT_BALANCE),
                  AccountInfoDouble(ACCOUNT_MARGIN_FREE)));
}

//+------------------------------------------------------------------+
double GetCapital()
{
   if(InpCapitalMode == CAPITAL_VIRTUAL)
      return GetVirtualCapital();
   if(InpCapitalMode == CAPITAL_MANUAL)
   {
      g_capitalSource = "manual";
      return MathMax(0.0, InpClearSaldo);
   }
   double broker = BrokerReportedCapital();
   if(InpCapitalMode == CAPITAL_BROKER)
   {
      g_capitalSource = "broker";
      return MathMax(0.0, broker);
   }
   if(broker >= InpBrokerMinReliable)
   {
      g_capitalSource = "broker";
      return broker;
   }
   return GetVirtualCapital();
}

//+------------------------------------------------------------------+
double ContractsFromCapitalBands(const double capital)
{
   if(capital < InpMinCapitalTrade || capital < InpBandStart)
      return 0.0;
   double width = InpBandWidth;
   if(width <= 0.0) width = 1000.0;
   double raw = MathFloor((capital - InpBandStart) / width + 1e-8) + 1.0;
   if(raw < 1.0) raw = 1.0;
   return ClampVolume(raw);
}

//+------------------------------------------------------------------+
double CalcVolume()
{
   if(InpSizingMode == SIZING_FIXED)
      return ClampVolume(InpFixedVolume);

   double capital = GetCapital();
   double raw = ContractsFromCapitalBands(capital);
   if(raw <= 0.0) return 0.0;

   double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(free > InpBrokerMinReliable)
   {
      double marginOne = 0.0;
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(price <= 0.0) price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(price > 0.0 && OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, price, marginOne) && marginOne > 0.0)
      {
         double byMargin = MathFloor(free / marginOne + 1e-8);
         if(byMargin < raw) raw = byMargin;
      }
   }
   return ClampVolume(raw);
}

//+------------------------------------------------------------------+
void LogSkip(const string reason)
{
   g_lastSkipReason = reason;
   if(InpVerboseLog)
      PrintFormat("OpenBreak: SKIP | %s", reason);
}

//+------------------------------------------------------------------+
double DailyLossLimitMoney()
{
   double base = (g_dayStartEquity > 0.0 ? g_dayStartEquity : GetCapital());
   return base * MathAbs(InpStopDiaPct) / 100.0;
}

//+------------------------------------------------------------------+
double DayPnLMoney()
{
   if(!HistorySelect(g_dayStart, TimeTradeServer() + 1))
      return FloatingPnLOurs();

   double pnl = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
         continue;
      pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT)
           + HistoryDealGetDouble(ticket, DEAL_SWAP)
           + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }
   return pnl + FloatingPnLOurs();
}

//+------------------------------------------------------------------+
bool DailyLossHit()
{
   return (DayPnLMoney() <= -DailyLossLimitMoney());
}

//+------------------------------------------------------------------+
int CountOurPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
double ATRPointsRaw()
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hATR, 0, 1, 1, atr) < 1 || _Point <= 0.0)
      return 200.0;
   return atr[0] / _Point;
}

//+------------------------------------------------------------------+
double TickSize()
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return (ts > 0.0 ? ts : _Point);
}

//+------------------------------------------------------------------+
double SnapPrice(const double price)
{
   double ts = TickSize();
   if(ts <= 0.0) return price;
   return NormalizeDouble(MathRound(price / ts) * ts, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
void NormalizeSL(const long orderOrPosType, const double price, double &sl)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int minDist = MinStopDistancePoints();
   double minGap = minDist * _Point;

   if(orderOrPosType == ORDER_TYPE_BUY || orderOrPosType == POSITION_TYPE_BUY)
   {
      if(sl > 0.0 && (price - sl) < minGap)
         sl = price - minGap;
   }
   else
   {
      if(sl > 0.0 && (sl - price) < minGap)
         sl = price + minGap;
   }
   sl = NormalizeDouble(SnapPrice(sl), digits);
}

//+------------------------------------------------------------------+
double MoneyPerPointPerContract()
{
   // WIN mini: tipicamente R$0,20 / ponto / contrato
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv > 0.0 && ts > 0.0 && _Point > 0.0)
      return tv * (_Point / ts);
   return 0.20;
}

//+------------------------------------------------------------------+
double ClampSLPoints(const double rawPts)
{
   double pts = rawPts;
   if(pts < InpMinSL_Points) pts = InpMinSL_Points;
   if(pts > InpMaxSL_Points) pts = InpMaxSL_Points;

   double cap = GetCapital();
   double vol = MathMax(CalcVolume(), 1.0);
   double mpp = MoneyPerPointPerContract();
   if(cap > 0.0 && mpp > 0.0 && InpMaxSL_CapitalPct > 0.0)
   {
      double maxMoney = cap * InpMaxSL_CapitalPct / 100.0;
      double maxPts = maxMoney / (mpp * vol);
      if(maxPts > 0.0 && pts > maxPts)
         pts = maxPts;
   }
   if(pts < InpMinSL_Points) pts = InpMinSL_Points;
   return pts;
}

//+------------------------------------------------------------------+
void AppendDayHistory(const datetime dayStamp, const double dayStartCap, const double dayPnL, const double dayEndCap, const double vol)
{
   if(!InpSaveDayHistory) return;
   string path = InpHistoryFile;
   int h = FileOpen(path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
      h = FileOpen(path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   if(FileTell(h) == 0)
      FileWriteString(h, "day,dayStartCap,dayPnL,dayEndCap,vol\n");
   FileWriteString(h, StringFormat("%s,%.2f,%.2f,%.2f,%.0f\n",
                                   TimeToString(dayStamp, TIME_DATE), dayStartCap, dayPnL, dayEndCap, vol));
   FileClose(h);
}

//+------------------------------------------------------------------+
void ResetDayIfNeeded()
{
   datetime now = TimeTradeServer();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   datetime day0 = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));

   if(g_dayStart == day0)
      return;

   if(g_dayStart > 0)
   {
      double endCap = GetCapital();
      AppendDayHistory(g_dayStart, g_dayStartEquity, DayPnLMoney(), endCap, CalcVolume());
   }

   g_dayStart = day0;
   g_dayStartEquity = GetCapital();
   g_dayStopped = false;
   g_loggedDailyFlat = false;
   g_tradesToday = 0;
   g_lastBarTime = 0;
   g_boxHigh = 0.0;
   g_boxLow = 0.0;
   g_boxReady = false;
   g_boxLogged = false;
   g_beDone = false;
   g_lastSkipReason = "";

   PrintFormat("OpenBreak: novo dia | capital R$%.2f (%s) | stopDia=%.1f%% (R$%.0f)",
               g_dayStartEquity, g_capitalSource, InpStopDiaPct, DailyLossLimitMoney());
}

//+------------------------------------------------------------------+
void BuildOrUpdateBox(const datetime now)
{
   if(g_boxReady)
      return;

   if(!BoxShouldBeReady(now) && !InBoxBuildWindow(now))
      return;

   datetime from = g_dayStart + HM(InpBoxStartH, InpBoxStartM) * 60;
   datetime to   = g_dayStart + HM(InpBoxEndH, InpBoxEndM) * 60;

   // Enquanto a caixa ainda está se formando, só atualiza high/low parcial
   datetime toScan = (BoxShouldBeReady(now) ? to : now);
   if(toScan <= from)
      return;

   double hi = 0.0, lo = 0.0;
   bool any = false;
   int bars = Bars(_Symbol, InpTF);
   for(int i = 0; i < bars; i++)
   {
      datetime bt = iTime(_Symbol, InpTF, i);
      if(bt == 0) break;
      if(bt >= to) continue;          // barra que começa no fim da caixa: fora
      if(bt < from) break;            // séries antigas

      double h = iHigh(_Symbol, InpTF, i);
      double l = iLow(_Symbol, InpTF, i);
      if(!any)
      {
         hi = h; lo = l; any = true;
      }
      else
      {
         if(h > hi) hi = h;
         if(l < lo) lo = l;
      }
   }

   if(!any)
      return;

   g_boxHigh = SnapPrice(hi);
   g_boxLow  = SnapPrice(lo);

   if(BoxShouldBeReady(now))
   {
      double boxPts = (g_boxHigh - g_boxLow) / _Point;
      if(boxPts < InpMinBoxPts)
      {
         g_boxReady = true; // marca p/ não insistir; não opera
         if(!g_boxLogged)
         {
            g_boxLogged = true;
            PrintFormat("OpenBreak: caixa estreita %.0f pts < min %.0f — sem trade hoje",
                        boxPts, InpMinBoxPts);
         }
         return;
      }
      if(boxPts > InpMaxBoxPts)
      {
         g_boxReady = true;
         if(!g_boxLogged)
         {
            g_boxLogged = true;
            PrintFormat("OpenBreak: caixa larga %.0f pts > max %.0f — sem trade hoje",
                        boxPts, InpMaxBoxPts);
         }
         return;
      }

      g_boxReady = true;
      if(!g_boxLogged)
      {
         g_boxLogged = true;
         PrintFormat("OpenBreak: CAIXA pronta high=%.0f low=%.0f range=%.0f pts | entradas até %02d:%02d | flat %02d:%02d",
                     g_boxHigh, g_boxLow, boxPts,
                     InpEntryEndH, InpEntryEndM, InpFlatH, InpFlatM);
      }
   }
}

//+------------------------------------------------------------------+
bool VolumeOk(const int shift)
{
   if(!InpUseVolumeFilter)
      return true;
   if(hVol == INVALID_HANDLE)
      return true;

   double vol[];
   ArraySetAsSeries(vol, true);
   int need = InpVolAvgBars + 2;
   if(CopyBuffer(hVol, 0, shift, need, vol) < need)
      return false;

   double sum = 0.0;
   for(int i = 1; i <= InpVolAvgBars; i++)
      sum += vol[i];
   double avg = sum / InpVolAvgBars;
   if(avg <= 0.0) return false;
   return (vol[0] >= avg * InpVolMinX);
}

//+------------------------------------------------------------------+
// Sinal no candle fechado (shift 1): fecha fora da caixa + volume
bool GetBreakSignal(int &dir)
{
   dir = 0;
   if(!g_boxReady || g_boxHigh <= g_boxLow)
      return false;

   double boxPts = (g_boxHigh - g_boxLow) / _Point;
   if(boxPts < InpMinBoxPts || boxPts > InpMaxBoxPts)
   {
      LogSkip(StringFormat("caixa inválida %.0f pts", boxPts));
      return false;
   }

   double close1 = iClose(_Symbol, InpTF, 1);
   if(close1 <= 0.0) return false;

   double buf = InpBreakBufferPts * _Point;
   bool up = (close1 > g_boxHigh + buf);
   bool dn = (close1 < g_boxLow - buf);
   if(!up && !dn)
      return false;

   if(!VolumeOk(1))
   {
      LogSkip(StringFormat("volume fraco no rompimento (min %.2fx)", InpVolMinX));
      return false;
   }

   // Barra do sinal deve estar dentro da janela de entrada
   datetime barT = iTime(_Symbol, InpTF, 1);
   if(barT == 0 || !EntryWindowOpen(barT))
   {
      LogSkip("rompimento fora da janela de entrada");
      return false;
   }

   dir = up ? 1 : -1;
   return true;
}

//+------------------------------------------------------------------+
double ComputeSLPrice(const int dir, const double entry)
{
   double atrPts = ATRPointsRaw();
   double atrSL = ClampSLPoints(atrPts * InpSL_ATR_Mult);
   double sl = 0.0;

   if(InpSLBeyondBox && g_boxHigh > g_boxLow)
   {
      if(dir > 0)
      {
         sl = g_boxLow - InpBreakBufferPts * _Point;
         double distPts = (entry - sl) / _Point;
         if(distPts < InpMinSL_Points)
            sl = entry - atrSL * _Point;
         else if(distPts > InpMaxSL_Points)
            sl = entry - ClampSLPoints(distPts) * _Point;
      }
      else
      {
         sl = g_boxHigh + InpBreakBufferPts * _Point;
         double distPts = (sl - entry) / _Point;
         if(distPts < InpMinSL_Points)
            sl = entry + atrSL * _Point;
         else if(distPts > InpMaxSL_Points)
            sl = entry + ClampSLPoints(distPts) * _Point;
      }
   }
   else
   {
      sl = (dir > 0) ? (entry - atrSL * _Point) : (entry + atrSL * _Point);
   }

   NormalizeSL(dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, entry, sl);
   return sl;
}

//+------------------------------------------------------------------+
bool OpenTrade(const int dir)
{
   double vol = CalcVolume();
   if(vol <= 0.0)
   {
      PrintFormat("OpenBreak: sem volume (capital=R$%.2f)", GetCapital());
      return false;
   }

   int spread = CurrentSpreadPoints();
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints)
   {
      LogSkip(StringFormat("spread %d > %d", spread, InpMaxSpreadPoints));
      return false;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
   {
      Print("OpenBreak: sem cotação");
      return false;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool ok = false;
   double sl = 0.0;
   if(dir > 0)
   {
      sl = ComputeSLPrice(dir, ask);
      ok = trade.Buy(vol, _Symbol, ask, sl, 0.0, InpTradeComment);
   }
   else
   {
      sl = ComputeSLPrice(dir, bid);
      ok = trade.Sell(vol, _Symbol, bid, sl, 0.0, InpTradeComment);
   }

   if(ok)
   {
      g_tradesToday++;
      g_beDone = false;
      PrintFormat("OpenBreak: %s vol=%.0f entry≈%.0f SL=%.0f | caixa %.0f–%.0f | spread=%d | SEM meta%% — BE+trail",
                  (dir > 0 ? "BUY" : "SELL"), vol,
                  (dir > 0 ? ask : bid), sl, g_boxLow, g_boxHigh, spread);
   }
   else
      PrintFormat("OpenBreak: falha ordem retcode=%u %s", trade.ResultRetcode(), trade.ResultComment());

   return ok;
}

//+------------------------------------------------------------------+
void ManageBEAndTrail()
{
   double atrPts = ATRPointsRaw();
   double trailStart = atrPts * InpTrailStart_ATR;
   double trailDist  = atrPts * InpTrail_ATR;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double newSL = sl;

      if(type == POSITION_TYPE_BUY)
      {
         double profitPts = (bid - open) / _Point;

         // Break-even
         if(!g_beDone && profitPts >= InpBE_Points)
         {
            double beSL = open + InpBE_LockPoints * _Point;
            NormalizeSL(POSITION_TYPE_BUY, bid, beSL);
            if(sl <= 0.0 || beSL > sl)
            {
               newSL = beSL;
               g_beDone = true;
               if(InpVerboseLog)
                  PrintFormat("OpenBreak: BE armado BUY @ %.0f (lucro %.0f pts)", beSL, profitPts);
            }
         }

         // Trail para buscar máximo
         if(profitPts >= trailStart)
         {
            double trailSL = bid - trailDist * _Point;
            NormalizeSL(POSITION_TYPE_BUY, bid, trailSL);
            if(newSL <= 0.0 || trailSL > newSL)
               newSL = trailSL;
            if(sl > 0.0 && newSL < sl)
               newSL = sl;
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profitPts = (open - ask) / _Point;

         if(!g_beDone && profitPts >= InpBE_Points)
         {
            double beSL = open - InpBE_LockPoints * _Point;
            NormalizeSL(POSITION_TYPE_SELL, ask, beSL);
            if(sl <= 0.0 || beSL < sl)
            {
               newSL = beSL;
               g_beDone = true;
               if(InpVerboseLog)
                  PrintFormat("OpenBreak: BE armado SELL @ %.0f (lucro %.0f pts)", beSL, profitPts);
            }
         }

         if(profitPts >= trailStart)
         {
            double trailSL = ask + trailDist * _Point;
            NormalizeSL(POSITION_TYPE_SELL, ask, trailSL);
            if(newSL <= 0.0 || trailSL < newSL)
               newSL = trailSL;
            if(sl > 0.0 && newSL > sl)
               newSL = sl;
         }
      }

      if(newSL > 0.0 && MathAbs(newSL - sl) >= _Point)
      {
         if(!trade.PositionModify(ticket, newSL, 0.0) && InpVerboseLog)
            PrintFormat("OpenBreak: modify SL falhou %u", trade.ResultRetcode());
      }
   }
}

//+------------------------------------------------------------------+
void CloseAllOurs(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!trade.PositionClose(ticket) && InpVerboseLog)
         PrintFormat("OpenBreak: close falhou %I64u ret=%u (%s)",
                     ticket, trade.ResultRetcode(), reason);
   }
}

//+------------------------------------------------------------------+
void UpdateChartComment()
{
   string box = g_boxReady
      ? StringFormat("caixa %.0f–%.0f (%.0f pts)", g_boxLow, g_boxHigh, (g_boxHigh - g_boxLow) / _Point)
      : (InBoxBuildWindow(TimeTradeServer()) ? "montando caixa…" : "aguardando caixa");

   string phase = g_dayStopped ? "STOP DIA"
                : (ShouldFlat(TimeTradeServer()) ? "FLAT"
                : (EntryWindowOpen(TimeTradeServer()) ? "ENTRADA"
                : (InBoxBuildWindow(TimeTradeServer()) ? "CAIXA" : "FORA")));

   string txt = StringFormat(
      "OpenBreakWIN v1.00 | %s\n%s | %s\ncapital R$%.0f (%s) | vol≈%.0f | dayPnL R$%.0f\n"
      "trades %d/%d | BE %s | spread %d | sem meta%% — max da manhã\n%s",
      _Symbol, box, phase,
      GetCapital(), g_capitalSource, CalcVolume(), DayPnLMoney(),
      g_tradesToday, InpMaxTradesDay, (g_beDone ? "ON" : "off"),
      CurrentSpreadPoints(), g_lastSkipReason
   );
   Comment(txt);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(!IsWinSymbol())
      Print("OpenBreak: aviso — símbolo não parece WIN: ", _Symbol);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   EnsureSeedCapital();

   hATR = iATR(_Symbol, InpTF, InpATRPeriod);
   hVol = iVolumes(_Symbol, InpTF, VOLUME_TICK);
   if(hATR == INVALID_HANDLE)
   {
      Print("OpenBreak: falha ATR");
      return INIT_FAILED;
   }

   ResetDayIfNeeded();
   PrintFormat("OpenBreakWIN_v1.00 init | %s | capital=R$%.2f (%s) seed=R$%.2f | vol≈%.0f | magic=%I64d",
               _Symbol, GetCapital(), g_capitalSource, g_seedCapital, CalcVolume(), InpMagic);
   PrintFormat("OpenBreak: caixa %02d:%02d–%02d:%02d | entry até %02d:%02d | flat %02d:%02d | STOP DIA %.1f%% | SEM meta dia",
               InpBoxStartH, InpBoxStartM, InpBoxEndH, InpBoxEndM,
               InpEntryEndH, InpEntryEndM, InpFlatH, InpFlatM, InpStopDiaPct);
   PrintFormat("OpenBreak: BE=%d pts | trail start=%.2fxATR dist=%.2fxATR | maxTrades=%d",
               InpBE_Points, InpTrailStart_ATR, InpTrail_ATR, InpMaxTradesDay);
   UpdateChartComment();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hVol != INVALID_HANDLE) IndicatorRelease(hVol);
}

//+------------------------------------------------------------------+
void OnTick()
{
   ResetDayIfNeeded();
   datetime now = TimeTradeServer();
   BuildOrUpdateBox(now);
   UpdateChartComment();

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return;

   // Gerencia posição mesmo após janela de entrada (até flat)
   if(CountOurPositions() > 0 && !ShouldFlat(now) && !g_dayStopped)
      ManageBEAndTrail();

   if(ShouldFlat(now))
   {
      if(CountOurPositions() > 0)
         CloseAllOurs("flat_hour");
      return;
   }

   if(DailyLossHit() || g_dayStopped)
   {
      g_dayStopped = true;
      if(InpFlatOnDailyLoss && CountOurPositions() > 0)
      {
         if(!g_loggedDailyFlat)
         {
            PrintFormat("OpenBreak: STOP DIÁRIO | dayPnL=R$%.2f | limite=-R$%.2f → flat",
                        DayPnLMoney(), DailyLossLimitMoney());
            g_loggedDailyFlat = true;
         }
         CloseAllOurs("daily_loss");
      }
      return;
   }

   // Novas entradas só na janela
   if(!EntryWindowOpen(now))
      return;
   if(!g_boxReady)
      return;
   if(CountOurPositions() >= InpMaxPositions)
      return;
   if(g_tradesToday >= InpMaxTradesDay)
      return;

   datetime barTime = iTime(_Symbol, InpTF, 1);
   if(barTime == 0 || barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;

   int dir = 0;
   if(!GetBreakSignal(dir) || dir == 0)
      return;

   OpenTrade(dir);
}
//+------------------------------------------------------------------+
