//+------------------------------------------------------------------+
//| PullbackWIN_v1.mq5                                                |
//| Daytrade WIN (Clear) — pullback EMA20/50 + rompimento do sinal   |
//| Complemento do OpenBreak: sessão 11:05–15:45 (OpenBreak flat 11h)|
//| 1 contrato default | R:R 2.0 | STOP DIA 5% | telinha + logs      |
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
input ENUM_WIN_SIZING   InpSizingMode        = SIZING_FIXED; // Fixo 1: não empilhar com OpenBreak
input ENUM_CAPITAL_MODE InpCapitalMode       = CAPITAL_VIRTUAL;
input double InpClearSaldo        = 5353.45;
input double InpBandStart          = 500.0;
input double InpBandWidth          = 1000.0;
input double InpFixedVolume        = 1.0;     // Default 1 contrato (complemento tarde)
input double InpMaxVolume          = 10.0;
input double InpMinCapitalTrade    = 500.0;
input double InpBrokerMinReliable  = 50.0;
input bool   InpIncludeFloating    = true;
input bool   InpEstimateFees       = true;
input double InpFeePerSide         = 0.25;
input bool   InpResetVirtualSeed   = false;
input bool   InpSaveDayHistory     = true;
input string InpHistoryFile        = "PullbackWIN_v1_equity.csv";

input group "=== Risco diário ==="
input double InpStopDiaPct         = 5.0;
input bool   InpFlatOnDailyLoss    = true;
input int    InpMaxTradesDay       = 3;
input int    InpMaxPositions       = 1;
input int    InpMaxSpreadPoints    = 20;
input bool   InpBlockIfAnyPos      = true;    // Não entra se houver posição no símbolo (ex.: OpenBreak)

input group "=== Sessão (após OpenBreak flat 11:00) ==="
input int    InpSessStartH         = 11;
input int    InpSessStartM         = 5;       // 11:05
input int    InpSessEndH           = 15;
input int    InpSessEndM           = 45;      // sem novas entradas após
input int    InpFlatH              = 16;
input int    InpFlatM              = 0;

input group "=== Entrada (pullback EMA) ==="
input ENUM_TIMEFRAMES InpTF        = PERIOD_M5;
input int    InpFastEMA            = 20;
input int    InpSlowEMA            = 50;
input double InpRewardRisk         = 2.0;     // TP = R * risco
input int    InpBufferPricePoints  = 10;      // Folga SL além do candle (pts índice)
input int    InpEntryOffsetPts     = 5;       // Rompe high/low do sinal + offset
input int    InpMinRiskPts         = 80;      // Risco mínimo (pts)
input int    InpMaxRiskPts         = 500;     // Risco máximo (pts) — evita candle monstro

input group "=== Geral ==="
input long   InpMagic              = 260919;  // Único (OpenBreak=260918)
input int    InpSlippagePoints     = 30;
input string InpTradeComment       = "PullbackWIN_v1";
input bool   InpVerboseLog         = true;

//------------------------ Estado ------------------------------------
datetime g_dayStart = 0;
double   g_dayStartEquity = 0.0;
datetime g_barTime = 0;
bool     g_dayStopped = false;
bool     g_loggedDailyFlat = false;
int      g_tradesToday = 0;
string   g_capitalSource = "n/a";
string   g_lastSkipReason = "";
string   g_phase = "";

double   g_seedCapital = 0.0;
double   g_realizedAll = 0.0;
double   g_feesAll = 0.0;
datetime g_equityEpoch = 0;

// Sinal válido só durante a barra seguinte ao candle de pullback
int      g_signalDir = 0;
datetime g_signalBarTime = 0;
double   g_signalHigh = 0.0;
double   g_signalLow = 0.0;
bool     g_signalConsumed = false;

int hFast = INVALID_HANDLE;
int hSlow = INVALID_HANDLE;

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
bool SessionOpen(const datetime t)
{
   int now = MinutesOfDay(t);
   return (now >= HM(InpSessStartH, InpSessStartM) && now < HM(InpSessEndH, InpSessEndM));
}

//+------------------------------------------------------------------+
bool ShouldFlat(const datetime t)
{
   return (MinutesOfDay(t) >= HM(InpFlatH, InpFlatM));
}

//+------------------------------------------------------------------+
string GVPrefix()
{
   return StringFormat("PullbackWIN_v100_%I64d_", InpMagic);
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
      PrintFormat("Pullback: semente R$%.2f a partir de %s | GV %s",
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
      PrintFormat("Pullback: SKIP | %s", reason);
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
bool AnyPositionOnSymbol()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
   }
   return false;
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
void NormalizeSLTP(const bool isBuy, const double price, double &sl, double &tp)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double minGap = MinStopDistancePoints() * _Point;
   if(isBuy)
   {
      if(sl > 0.0 && (price - sl) < minGap) sl = price - minGap;
      if(tp > 0.0 && (tp - price) < minGap) tp = price + minGap;
   }
   else
   {
      if(sl > 0.0 && (sl - price) < minGap) sl = price + minGap;
      if(tp > 0.0 && (price - tp) < minGap) tp = price - minGap;
   }
   sl = NormalizeDouble(SnapPrice(sl), digits);
   tp = NormalizeDouble(SnapPrice(tp), digits);
}

//+------------------------------------------------------------------+
void AppendDayHistory(const datetime dayStamp, const double dayStartCap, const double dayPnL,
                      const double dayEndCap, const double vol)
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
      AppendDayHistory(g_dayStart, g_dayStartEquity, DayPnLMoney(), GetCapital(), CalcVolume());

   g_dayStart = day0;
   g_dayStartEquity = GetCapital();
   g_dayStopped = false;
   g_loggedDailyFlat = false;
   g_tradesToday = 0;
   g_barTime = 0;
   g_signalDir = 0;
   g_signalConsumed = false;
   g_lastSkipReason = "";

   PrintFormat("Pullback: novo dia | capital R$%.2f (%s) | stopDia=%.1f%% (R$%.0f) | sessão %02d:%02d–%02d:%02d",
               g_dayStartEquity, g_capitalSource, InpStopDiaPct, DailyLossLimitMoney(),
               InpSessStartH, InpSessStartM, InpSessEndH, InpSessEndM);
}

//+------------------------------------------------------------------+
void RefreshSignal()
{
   g_signalDir = 0;
   g_signalConsumed = false;
   g_signalHigh = 0.0;
   g_signalLow = 0.0;

   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   if(CopyRates(_Symbol, InpTF, 0, 3, bars) != 3)
      return;

   double f1[1], f2[1], s1[1];
   if(CopyBuffer(hFast, 0, 1, 1, f1) != 1) return;
   if(CopyBuffer(hFast, 0, 2, 1, f2) != 1) return;
   if(CopyBuffer(hSlow, 0, 1, 1, s1) != 1) return;

   MqlRates candle = bars[1];
   g_signalBarTime = candle.time;
   g_signalHigh = candle.high;
   g_signalLow = candle.low;

   // Pullback na EMA rápida a favor da tendência EMA20/50
   if(f1[0] > s1[0] && f1[0] > f2[0] &&
      candle.low <= f1[0] && candle.close > f1[0] && candle.close > candle.open)
   {
      g_signalDir = 1;
      if(InpVerboseLog)
         PrintFormat("Pullback: SINAL BUY | bar %s | hi=%.0f lo=%.0f | EMA%.0f=%.0f EMA%.0f=%.0f",
                     TimeToString(g_signalBarTime, TIME_MINUTES), g_signalHigh, g_signalLow,
                     (double)InpFastEMA, f1[0], (double)InpSlowEMA, s1[0]);
   }
   else if(f1[0] < s1[0] && f1[0] < f2[0] &&
           candle.high >= f1[0] && candle.close < f1[0] && candle.close < candle.open)
   {
      g_signalDir = -1;
      if(InpVerboseLog)
         PrintFormat("Pullback: SINAL SELL | bar %s | hi=%.0f lo=%.0f | EMA%.0f=%.0f EMA%.0f=%.0f",
                     TimeToString(g_signalBarTime, TIME_MINUTES), g_signalHigh, g_signalLow,
                     (double)InpFastEMA, f1[0], (double)InpSlowEMA, s1[0]);
   }
}

//+------------------------------------------------------------------+
bool OpenTrade(const int dir)
{
   double vol = CalcVolume();
   if(vol <= 0.0)
   {
      LogSkip(StringFormat("sem volume (capital=R$%.2f)", GetCapital()));
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
      LogSkip("sem cotação");
      return false;
   }

   double price = (dir > 0 ? ask : bid);
   // Buffer em pts de índice (WIN: _Point tipicamente 1.0)
   double sl = (dir > 0) ? (g_signalLow - InpBufferPricePoints) : (g_signalHigh + InpBufferPricePoints);
   if(_Point > 0.0 && MathAbs(_Point - 1.0) > 1e-8)
      sl = (dir > 0) ? (g_signalLow - InpBufferPricePoints * _Point)
                     : (g_signalHigh + InpBufferPricePoints * _Point);

   sl = SnapPrice(sl);
   double risk = MathAbs(price - sl);
   double riskPts = (_Point > 0.0 ? risk / _Point : risk);

   if(riskPts < InpMinRiskPts)
   {
      LogSkip(StringFormat("risco %.0f pts < min %d", riskPts, InpMinRiskPts));
      return false;
   }
   if(riskPts > InpMaxRiskPts)
   {
      LogSkip(StringFormat("risco %.0f pts > max %d (candle largo)", riskPts, InpMaxRiskPts));
      return false;
   }

   double tp = (dir > 0) ? (price + InpRewardRisk * risk) : (price - InpRewardRisk * risk);
   tp = SnapPrice(tp);
   NormalizeSLTP(dir > 0, price, sl, tp);

   if((dir > 0 && (sl >= bid || tp <= ask)) || (dir < 0 && (sl <= ask || tp >= bid)))
   {
      LogSkip("SL/TP inválidos após normalize");
      return false;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool ok = false;
   if(dir > 0)
      ok = trade.Buy(vol, _Symbol, ask, sl, tp, InpTradeComment);
   else
      ok = trade.Sell(vol, _Symbol, bid, sl, tp, InpTradeComment);

   if(ok)
   {
      g_tradesToday++;
      PrintFormat("Pullback: %s vol=%.0f entry≈%.0f SL=%.0f TP=%.0f | risk≈%.0f pts R:R=%.1f | spread=%d",
                  (dir > 0 ? "BUY" : "SELL"), vol, price, sl, tp, riskPts, InpRewardRisk, spread);
   }
   else
      PrintFormat("Pullback: falha ordem ret=%u %s", trade.ResultRetcode(), trade.ResultComment());

   return ok;
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
         PrintFormat("Pullback: close falhou %I64u ret=%u (%s)",
                     ticket, trade.ResultRetcode(), reason);
   }
}

//+------------------------------------------------------------------+
void UpdateChartComment()
{
   datetime now = TimeTradeServer();
   string sinal = "—";
   if(g_signalDir > 0 && !g_signalConsumed)
      sinal = StringFormat("BUY wait>%.0f", g_signalHigh + InpEntryOffsetPts);
   else if(g_signalDir < 0 && !g_signalConsumed)
      sinal = StringFormat("SELL wait<%.0f", g_signalLow - InpEntryOffsetPts);
   else if(g_signalConsumed)
      sinal = "sinal consumido";

   g_phase = g_dayStopped ? "STOP DIA"
           : (ShouldFlat(now) ? "FLAT"
           : (SessionOpen(now) ? "SESSÃO" : "FORA (aguarda 11:05)"));

   string txt = StringFormat(
      "PullbackWIN v1.00 | %s\n"
      "EMA %d/%d | R:R %.1f | %s | %s\n"
      "capital R$%.0f (%s) | vol≈%.0f | dayPnL R$%.0f\n"
      "trades %d/%d | spread %d | após OpenBreak (flat 11:00)\n"
      "%s",
      _Symbol,
      InpFastEMA, InpSlowEMA, InpRewardRisk, g_phase, sinal,
      GetCapital(), g_capitalSource, CalcVolume(), DayPnLMoney(),
      g_tradesToday, InpMaxTradesDay, CurrentSpreadPoints(),
      g_lastSkipReason
   );
   Comment(txt);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(!IsWinSymbol())
      Print("Pullback: aviso — símbolo não parece WIN: ", _Symbol);

   if(InpFastEMA < 2 || InpSlowEMA <= InpFastEMA || InpRewardRisk <= 0.0 ||
      InpMaxTradesDay < 1 || InpStopDiaPct <= 0.0 ||
      HM(InpSessStartH, InpSessStartM) >= HM(InpSessEndH, InpSessEndM))
      return INIT_PARAMETERS_INCORRECT;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   EnsureSeedCapital();

   hFast = iMA(_Symbol, InpTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, InpTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE)
   {
      Print("Pullback: falha EMA");
      return INIT_FAILED;
   }

   ResetDayIfNeeded();
   PrintFormat("PullbackWIN_v1.00 init | %s | capital=R$%.2f (%s) seed=R$%.2f | vol≈%.0f | magic=%I64d",
               _Symbol, GetCapital(), g_capitalSource, g_seedCapital, CalcVolume(), InpMagic);
   PrintFormat("Pullback: sessão %02d:%02d–%02d:%02d | flat %02d:%02d | STOP DIA %.1f%% | maxTrades=%d | R:R=%.1f",
               InpSessStartH, InpSessStartM, InpSessEndH, InpSessEndM,
               InpFlatH, InpFlatM, InpStopDiaPct, InpMaxTradesDay, InpRewardRisk);
   PrintFormat("Pullback: complemento do OpenBreak — não entra antes das 11:05 | volume default fixo %.0f",
               InpFixedVolume);
   UpdateChartComment();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   if(hFast != INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow != INVALID_HANDLE) IndicatorRelease(hSlow);
}

//+------------------------------------------------------------------+
void OnTick()
{
   ResetDayIfNeeded();
   datetime now = TimeTradeServer();
   UpdateChartComment();

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return;

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
            PrintFormat("Pullback: STOP DIÁRIO | dayPnL=R$%.2f | limite=-R$%.2f → flat",
                        DayPnLMoney(), DailyLossLimitMoney());
            g_loggedDailyFlat = true;
         }
         CloseAllOurs("daily_loss");
      }
      return;
   }

   if(!SessionOpen(now))
      return;

   // Nova barra M5 → avalia sinal no candle fechado (válido só nesta barra)
   datetime currentBar = iTime(_Symbol, InpTF, 0);
   if(currentBar == 0) return;
   if(currentBar != g_barTime)
   {
      g_barTime = currentBar;
      RefreshSignal();
   }

   if(g_signalDir == 0 || g_signalConsumed)
      return;
   if(CountOurPositions() >= InpMaxPositions)
      return;
   if(g_tradesToday >= InpMaxTradesDay)
      return;
   if(InpBlockIfAnyPos && AnyPositionOnSymbol())
   {
      g_lastSkipReason = "posição aberta no símbolo (aguarda flat OpenBreak)";
      return;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;

   double offset = (double)InpEntryOffsetPts;
   if(_Point > 0.0 && MathAbs(_Point - 1.0) > 1e-8)
      offset = InpEntryOffsetPts * _Point;

   bool triggered = false;
   if(g_signalDir > 0)
      triggered = (ask >= g_signalHigh + offset);
   else
      triggered = (bid <= g_signalLow - offset);

   if(!triggered)
      return;

   // Consome o sinal mesmo se a ordem falhar (evita spam)
   g_signalConsumed = true;
   OpenTrade(g_signalDir);
}
//+------------------------------------------------------------------+
