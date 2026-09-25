//+------------------------------------------------------------------+
//| ScalpUSDJPY_v3.mq5                                               |
//| Nomo - daytrade USDJPY | port da lógica ScalpWIN v2.08           |
//| Rompimento M5 + EMA/ADX + escada % + soft lock                   |
//| META DIA +3% (só bloqueia entradas) | STOP DIA 10% (pode flat)   |
//| Sessão Londres/NY | flat antes do swap | só seg–sex              |
//| v3.01: log a cada barra + filtro dia útil (seg–sex)              |
//+------------------------------------------------------------------+
#property copyright "Vitor / mt5-eas"
#property version   "3.01"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_SIZING
{
   SIZING_RISK_PCT = 0,  // Lote pelo risco % do saldo vs SL
   SIZING_FIXED    = 1   // Lote fixo
};

//------------------------ Inputs ------------------------------------
input group "=== Volume / risco ==="
input ENUM_SIZING InpSizingMode     = SIZING_RISK_PCT;
input double InpRiskPercent         = 0.50;   // Risco por trade (% saldo)
input double InpFixedLots           = 0.01;
input double InpMaxLots             = 0.50;
input double InpMinLots             = 0.01;

input group "=== Risco diário ==="
input double InpDailyLossPercent    = 10.0;   // STOP DIA: prejuízo >= X% do capital do dia
input bool   InpFlatOnDailyLoss     = true;   // true = fecha posições no STOP DIA
input double InpDailyWinPercent     = 3.0;    // META DIA: lucro >= X% do capital do dia
input bool   InpUseDailyWinMeta     = true;   // true = ao bater meta, não abre mais
input int    InpMaxPositions        = 1;
input int    InpMaxSpreadPoints     = 35;     // USDJPY Nomo: spread baixo

input group "=== Sessão (horário do servidor Nomo) ==="
input bool   InpWeekdaysOnly        = true;   // true = só segunda a sexta
input int    InpSessStartH          = 8;      // ~Londres
input int    InpSessStartM          = 0;
input int    InpSessEndH            = 17;     // ~NY tarde
input int    InpSessEndM            = 0;
input int    InpFlatH               = 20;     // Flat antes do swap
input int    InpFlatM               = 50;

input group "=== Entrada (rompimento) — mesmos filtros ScalpWIN ==="
input int    InpBreakN              = 3;
input int    InpEMAFast             = 50;
input int    InpEMASlow             = 200;
input bool   InpUseEmaTrend         = true;
input int    InpADXPeriod           = 14;
input double InpAdxGate             = 18.0;
input bool   InpUseADXFilter        = true;
input double InpBodyMin             = 0.25;   // Corpo mínimo × ATR
input bool   InpUseVolumeFilter     = true;
input int    InpVolAvgBars          = 20;
input double InpVolGate             = 0.85;
input ENUM_TIMEFRAMES InpTF         = PERIOD_M5;

input group "=== Stop (ATR, teto em % do capital) ==="
input double InpSL_ATR_Mult         = 1.50;
input int    InpATRPeriod           = 14;
input double InpMaxSL_CapitalPct    = 5.0;
input int    InpMinSL_Points        = 50;     // USDJPY (pts do símbolo)
input int    InpMaxSL_Points        = 500;

input group "=== Escada de lucro (% do capital do dia) ==="
input double InpLadder1_Pct         = 2.0;    // 1º alvo → fecha 50%
input double InpLadder1_CloseFrac   = 0.50;
input double InpLadder2_Pct         = 5.0;    // 2º alvo → fecha +25%
input double InpLadder2_CloseFrac   = 0.25;
input double InpLadder3_Pct         = 8.0;
input double InpLadder3_CloseFrac   = 0.25;
input bool   InpUseLadder3          = false;  // resto = soft lock

input group "=== Soft lock (runner) ==="
input double InpSoftStart_ATR       = 0.80;
input double InpSoftLock_ATR        = 0.30;
input double InpTrail_ATR           = 0.50;
input double InpSoftTightenAfter1   = 0.85;
input double InpSoftTightenAfter2   = 0.70;

input group "=== Geral ==="
input long   InpMagic               = 260831; // novo vs ScalpUSDJPY_v2 (260830)
input int    InpSlippagePoints      = 30;
input string InpTradeComment        = "ScalpUSDJPY_v3";
input bool   InpVerboseLog          = true;

//------------------------ Estado ------------------------------------
datetime g_dayStart = 0;
double   g_dayStartEquity = 0.0;
datetime g_lastBarTime = 0;
bool     g_dayStopped = false;
bool     g_dayWinMeta = false;
bool     g_loggedDailyFlat = false;
bool     g_loggedDailyWin  = false;
string   g_lastSkipReason = "";

ulong    g_posTicket = 0;
double   g_posOpenVol = 0.0;
double   g_posOpenPrice = 0.0;
int      g_ladderStep = 0;
double   g_realizedThisTrade = 0.0;
datetime g_lastCloseFailLog = 0;

int hEMA50  = INVALID_HANDLE;
int hEMA200 = INVALID_HANDLE;
int hADX    = INVALID_HANDLE;
int hATR    = INVALID_HANDLE;
int hVol    = INVALID_HANDLE;

//+------------------------------------------------------------------+
double NormalizeLots(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   if(minLot <= 0.0) minLot = 0.01;
   lots = MathFloor(lots / step + 1e-12) * step;
   lots = MathMax(InpMinLots, MathMin(InpMaxLots, lots));
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
double RoundDownVolume(const double v)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0.0) step = 0.01;
   double out = MathFloor(v / step + 1e-12) * step;
   if(out < vmin) out = 0.0;
   return out;
}

//+------------------------------------------------------------------+
int CurrentSpreadPoints()
{
   long spr = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spr > 0) return (int)spr;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0 || _Point <= 0.0) return 999999;
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
double TickSize()
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0) ts = _Point;
   if(ts <= 0.0) ts = 0.001;
   return ts;
}

//+------------------------------------------------------------------+
double SnapPrice(const double price)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
double MoneyPerPointPerLot()
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || _Point <= 0.0)
      return 0.0;
   return (tickValue / tickSize) * _Point;
}

//+------------------------------------------------------------------+
double GetCapital()
{
   return MathMax(AccountInfoDouble(ACCOUNT_EQUITY), AccountInfoDouble(ACCOUNT_BALANCE));
}

//+------------------------------------------------------------------+
void LogSkip(const string reason)
{
   // Igual ScalpWIN: imprime a cada chamada (cada barra nova) para o Experts não ficar mudo
   g_lastSkipReason = reason;
   if(InpVerboseLog)
      PrintFormat("ScalpJPY3: SKIP | %s", reason);
}

//+------------------------------------------------------------------+
double DailyLossLimitMoney()
{
   double base = (g_dayStartEquity > 0.0 ? g_dayStartEquity : GetCapital());
   return base * MathAbs(InpDailyLossPercent) / 100.0;
}

//+------------------------------------------------------------------+
double DailyWinTargetMoney()
{
   double base = (g_dayStartEquity > 0.0 ? g_dayStartEquity : GetCapital());
   return base * MathAbs(InpDailyWinPercent) / 100.0;
}

//+------------------------------------------------------------------+
double DayPnLMoney()
{
   datetime from = g_dayStart;
   datetime to = TimeTradeServer() + 1;
   if(!HistorySelect(from, to))
      return 0.0;

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
bool DailyLossHit()
{
   double limit = DailyLossLimitMoney();
   if(limit <= 0.0) return false;
   return (DayPnLMoney() <= -limit);
}

//+------------------------------------------------------------------+
bool DailyWinHit()
{
   if(!InpUseDailyWinMeta) return false;
   double target = DailyWinTargetMoney();
   if(target <= 0.0) return false;
   return (DayPnLMoney() >= target);
}

//+------------------------------------------------------------------+
void ResetPosState()
{
   g_posTicket = 0;
   g_posOpenVol = 0.0;
   g_posOpenPrice = 0.0;
   g_ladderStep = 0;
   g_realizedThisTrade = 0.0;
}

//+------------------------------------------------------------------+
void ResetDayIfNeeded()
{
   datetime now = TimeTradeServer();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   datetime day0 = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
   if(day0 != g_dayStart)
   {
      g_dayStart = day0;
      g_dayStartEquity = GetCapital();
      g_dayStopped = false;
      g_dayWinMeta = false;
      g_loggedDailyFlat = false;
      g_loggedDailyWin = false;
      g_lastSkipReason = "";
      PrintFormat("ScalpJPY3: novo dia | capital=%.2f | stopDia=%.2f | metaDia=%.2f",
                  g_dayStartEquity, DailyLossLimitMoney(), DailyWinTargetMoney());
   }
}

//+------------------------------------------------------------------+
bool IsWeekday(const datetime now)
{
   MqlDateTime dt;
   TimeToStruct(now, dt);
   // 0=domingo … 6=sábado (MqlDateTime.day_of_week)
   return (dt.day_of_week >= 1 && dt.day_of_week <= 5);
}

//+------------------------------------------------------------------+
bool SessionOpen(const datetime now)
{
   if(InpWeekdaysOnly && !IsWeekday(now))
      return false;

   MqlDateTime dt;
   TimeToStruct(now, dt);
   int nowMin = dt.hour * 60 + dt.min;
   return (nowMin >= InpSessStartH * 60 + InpSessStartM &&
           nowMin <  InpSessEndH * 60 + InpSessEndM);
}

//+------------------------------------------------------------------+
string SessionStatusText(const datetime now)
{
   if(InpWeekdaysOnly && !IsWeekday(now))
      return "FORA FDS";
   if(SessionOpen(now))
      return "SESSÃO";
   return "FORA";
}

//+------------------------------------------------------------------+
bool ShouldFlat(const datetime now)
{
   MqlDateTime dt;
   TimeToStruct(now, dt);
   // Fim de semana: se ainda houver posição, flat também
   if(InpWeekdaysOnly && !IsWeekday(now))
      return true;
   return ((dt.hour * 60 + dt.min) >= InpFlatH * 60 + InpFlatM);
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
bool SelectOurPosition(ulong &ticket, long &type, double &vol, double &open, double &sl, double &profit)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      type = PositionGetInteger(POSITION_TYPE);
      vol = PositionGetDouble(POSITION_VOLUME);
      open = PositionGetDouble(POSITION_PRICE_OPEN);
      sl = PositionGetDouble(POSITION_SL);
      profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool Copy1(const int handle, const int buffer, double &out)
{
   double a[];
   if(CopyBuffer(handle, buffer, 1, 1, a) != 1)
      return false;
   out = a[0];
   return true;
}

//+------------------------------------------------------------------+
double ATRPrice()
{
   double atr = 0.0;
   if(!Copy1(hATR, 0, atr) || atr <= 0.0)
      return InpMinSL_Points * _Point;
   return atr;
}

//+------------------------------------------------------------------+
double ATRPointsRaw()
{
   double pt = _Point;
   if(pt <= 0.0) pt = 0.001;
   return ATRPrice() / pt;
}

//+------------------------------------------------------------------+
double ClampSLPoints(const double pts)
{
   double out = pts;
   if(out < InpMinSL_Points) out = InpMinSL_Points;
   if(out > InpMaxSL_Points) out = InpMaxSL_Points;
   return out;
}

//+------------------------------------------------------------------+
double CalcSLPoints(const double lots)
{
   double slPts = ClampSLPoints(ATRPointsRaw() * InpSL_ATR_Mult);

   double cap = (g_dayStartEquity > 0.0 ? g_dayStartEquity : GetCapital());
   double maxMoney = cap * MathAbs(InpMaxSL_CapitalPct) / 100.0;
   double mpp = MoneyPerPointPerLot();
   if(mpp > 0.0 && lots > 0.0 && maxMoney > 0.0)
   {
      double maxPts = maxMoney / (mpp * lots);
      if(maxPts > 0.0 && slPts > maxPts)
         slPts = maxPts;
   }
   return ClampSLPoints(slPts);
}

//+------------------------------------------------------------------+
double CalcLots(const double slPts)
{
   if(InpSizingMode == SIZING_FIXED)
      return NormalizeLots(InpFixedLots);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0) balance = GetCapital();
   double moneyRisk = balance * MathAbs(InpRiskPercent) / 100.0;
   double mpp = MoneyPerPointPerLot();
   if(mpp <= 0.0 || slPts <= 0.0)
      return NormalizeLots(InpMinLots);

   double lossPerLot = mpp * slPts;
   if(lossPerLot <= 0.0)
      return NormalizeLots(InpMinLots);

   return NormalizeLots(MathMin(moneyRisk / lossPerLot, InpMaxLots));
}

//+------------------------------------------------------------------+
bool NormalizeSL(const long type, const double price, double &sl)
{
   if(sl <= 0.0 || price <= 0.0 || _Point <= 0.0)
      return false;

   double minDist = MathMax(MinStopDistancePoints() * _Point, TickSize());
   minDist += TickSize();

   bool isBuy = (type == POSITION_TYPE_BUY || type == ORDER_TYPE_BUY);
   if(isBuy)
   {
      if(price - sl < minDist)
         sl = price - minDist;
      sl = SnapPrice(sl);
      if(price - sl < minDist)
         sl = SnapPrice(price - minDist);
   }
   else
   {
      if(sl - price < minDist)
         sl = price + minDist;
      sl = SnapPrice(sl);
      if(sl - price < minDist)
         sl = SnapPrice(price + minDist);
   }
   return (sl > 0.0);
}

//+------------------------------------------------------------------+
bool VolumeOK(string &why)
{
   why = "";
   if(!InpUseVolumeFilter)
      return true;

   int need = MathMax(InpVolAvgBars + 2, 5);
   long vols[];
   ArraySetAsSeries(vols, true);
   if(CopyTickVolume(_Symbol, InpTF, 1, need, vols) < need)
   {
      why = "volume sem dados";
      return false;
   }

   long v1 = vols[0];
   double sum = 0.0;
   for(int i = 1; i <= InpVolAvgBars; i++)
      sum += (double)vols[i];
   double avg = sum / InpVolAvgBars;
   if(avg <= 0.0)
   {
      why = "média volume zerada";
      return false;
   }

   double mult = (double)v1 / avg;
   if(mult < InpVolGate)
   {
      why = StringFormat("volume fraco %.2fx < %.2fx", mult, InpVolGate);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool GetSignal(int &dir)
{
   dir = 0;
   double ema50, ema200, adx, atr;
   if(!Copy1(hEMA50, 0, ema50)) { LogSkip("EMA50 sem dados"); return false; }
   if(!Copy1(hEMA200, 0, ema200)) { LogSkip("EMA200 sem dados"); return false; }
   if(!Copy1(hADX, 0, adx)) { LogSkip("ADX sem dados"); return false; }
   if(!Copy1(hATR, 0, atr) || atr <= 0.0) { LogSkip("ATR sem dados"); return false; }

   if(InpUseADXFilter && adx < InpAdxGate)
   {
      LogSkip(StringFormat("ADX fraco %.1f < %.1f", adx, InpAdxGate));
      return true;
   }

   string volWhy = "";
   if(!VolumeOK(volWhy))
   {
      LogSkip(volWhy);
      return true;
   }

   double open1 = iOpen(_Symbol, InpTF, 1);
   double close1 = iClose(_Symbol, InpTF, 1);
   if(open1 <= 0.0 || close1 <= 0.0) { LogSkip("candle 1 sem OHLC"); return false; }

   double body = MathAbs(close1 - open1);
   double minBody = atr * InpBodyMin;
   if(body < minBody)
   {
      LogSkip(StringFormat("corpo fraco %.1f < %.1f pts", body / _Point, minBody / _Point));
      return true;
   }

   int bars = MathMax(2, InpBreakN);
   double hh = iHigh(_Symbol, InpTF, 2);
   double ll = iLow(_Symbol, InpTF, 2);
   for(int i = 3; i <= bars; i++)
   {
      hh = MathMax(hh, iHigh(_Symbol, InpTF, i));
      ll = MathMin(ll, iLow(_Symbol, InpTF, i));
   }

   bool bull = (close1 > open1);
   bool bear = (close1 < open1);
   bool upTrend = (ema50 > ema200);
   bool downTrend = (ema50 < ema200);

   if(bull && close1 > hh)
   {
      if(InpUseEmaTrend && !upTrend)
      {
         LogSkip("rompimento alta mas EMA contra");
         return true;
      }
      dir = 1;
      g_lastSkipReason = "";
      if(InpVerboseLog)
         PrintFormat("ScalpJPY3: SINAL BUY | close=%.3f > hh=%.3f | ADX=%.1f", close1, hh, adx);
      return true;
   }

   if(bear && close1 < ll)
   {
      if(InpUseEmaTrend && !downTrend)
      {
         LogSkip("rompimento baixa mas EMA contra");
         return true;
      }
      dir = -1;
      g_lastSkipReason = "";
      if(InpVerboseLog)
         PrintFormat("ScalpJPY3: SINAL SELL | close=%.3f < ll=%.3f | ADX=%.1f", close1, ll, adx);
      return true;
   }

   LogSkip(StringFormat("sem rompimento close=%.3f hh=%.3f ll=%.3f ADX=%.1f", close1, hh, ll, adx));
   return true;
}

//+------------------------------------------------------------------+
bool OpenTrade(const int dir)
{
   int spread = CurrentSpreadPoints();
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints)
   {
      LogSkip(StringFormat("spread %d > %d", spread, InpMaxSpreadPoints));
      return false;
   }

   // Pré-cálculo de SL em pts com lote provisório para sizing
   double slPtsProbe = ClampSLPoints(ATRPointsRaw() * InpSL_ATR_Mult);
   double lots = CalcLots(slPtsProbe);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      LogSkip(StringFormat("lote insuficiente (cap=%.2f)", GetCapital()));
      return false;
   }

   double slPts = CalcSLPoints(lots);
   // Recalcula lote com SL final (teto % capital pode apertar)
   lots = CalcLots(slPts);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
   {
      Print("ScalpJPY3: sem cotação");
      return false;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool ok = false;
   double sl = 0.0;
   if(dir > 0)
   {
      double entry = SnapPrice(ask);
      sl = entry - slPts * _Point;
      NormalizeSL(ORDER_TYPE_BUY, bid, sl);
      ok = trade.Buy(lots, _Symbol, entry, sl, 0.0, InpTradeComment);
   }
   else
   {
      double entry = SnapPrice(bid);
      sl = entry + slPts * _Point;
      NormalizeSL(ORDER_TYPE_SELL, ask, sl);
      ok = trade.Sell(lots, _Symbol, entry, sl, 0.0, InpTradeComment);
   }

   if(ok)
   {
      ResetPosState();
      g_posOpenVol = lots;
      g_posOpenPrice = (dir > 0 ? ask : bid);
      double mpp = MoneyPerPointPerLot();
      double slMoney = (mpp > 0.0 ? mpp * slPts * lots : 0.0);
      PrintFormat("ScalpJPY3: %s lots=%.2f SL=%.3f SLpts=%.0f (~%.2f) spread=%d",
                  (dir > 0 ? "BUY" : "SELL"), lots, sl, slPts, slMoney, spread);
   }
   else
      PrintFormat("ScalpJPY3: falha ordem ret=%u %s | ask=%.3f bid=%.3f sl=%.3f",
                  trade.ResultRetcode(), trade.ResultComment(), ask, bid, sl);

   return ok;
}

//+------------------------------------------------------------------+
bool CloseVolume(const ulong ticket, const double volClose, const string reason)
{
   if(volClose <= 0.0) return false;
   if(!PositionSelectByTicket(ticket))
      return false;

   double posVol = PositionGetDouble(POSITION_VOLUME);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double want = RoundDownVolume(volClose);
   if(want < vmin) return false;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(want >= posVol - 1e-8)
   {
      if(!trade.PositionClose(ticket))
      {
         datetime now = TimeTradeServer();
         if(now != g_lastCloseFailLog)
         {
            g_lastCloseFailLog = now;
            PrintFormat("ScalpJPY3: CLOSE total falhou %s vol=%.2f ret=%u %s",
                        reason, posVol, trade.ResultRetcode(), trade.ResultComment());
         }
         return false;
      }
      PrintFormat("ScalpJPY3: ZEROU %s | vol=%.2f | step=%d", reason, posVol, g_ladderStep);
      return true;
   }

   if(!trade.PositionClosePartial(ticket, want))
   {
      datetime now = TimeTradeServer();
      if(now != g_lastCloseFailLog)
      {
         g_lastCloseFailLog = now;
         PrintFormat("ScalpJPY3: parcial falhou %s vol=%.2f ret=%u — tentando close total",
                     reason, want, trade.ResultRetcode());
      }
      if(!trade.PositionClose(ticket))
         return false;
      PrintFormat("ScalpJPY3: ZEROU (fallback) %s | vol=%.2f", reason, posVol);
      return true;
   }
   PrintFormat("ScalpJPY3: PARCIAL %s | fechou %.2f de %.2f | step=%d", reason, want, posVol, g_ladderStep);
   return true;
}

//+------------------------------------------------------------------+
double TradeProfitMoney(const double floating)
{
   return floating + g_realizedThisTrade;
}

//+------------------------------------------------------------------+
void SyncPosStateFromMarket()
{
   ulong ticket; long type; double vol, open, sl, profit;
   if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
   {
      if(g_posTicket != 0 || g_posOpenVol > 0.0)
         ResetPosState();
      return;
   }

   if(g_posTicket == 0 || g_posTicket != ticket)
   {
      g_posTicket = ticket;
      if(g_posOpenVol <= 0.0)
         g_posOpenVol = vol;
      g_posOpenPrice = open;
   }
}

//+------------------------------------------------------------------+
void ManageLadderAndSoftLock()
{
   SyncPosStateFromMarket();

   ulong ticket; long type; double vol, open, sl, profit;
   if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
      return;

   g_posTicket = ticket;
   if(g_posOpenVol <= 0.0)
      g_posOpenVol = vol;

   double cap = (g_dayStartEquity > 0.0 ? g_dayStartEquity : GetCapital());
   if(cap <= 0.0) return;

   double tradePnL = TradeProfitMoney(profit);
   double tradePct = 100.0 * tradePnL / cap;
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   // Micro-lote (~0.01): não dá para parcial útil → zera no L1 (igual 1 contrato WIN)
   bool microLot = (g_posOpenVol < 2.0 * vmin - 1e-8);

   if(g_ladderStep < 1 && tradePct >= InpLadder1_Pct)
   {
      double want = RoundDownVolume(g_posOpenVol * InpLadder1_CloseFrac);
      if(microLot)
         want = vol;
      want = MathMin(want, vol);
      if(want >= vmin - 1e-8)
      {
         double before = profit;
         if(CloseVolume(ticket, want, StringFormat("L1 %.1f%% cap (pnl %.2f)", InpLadder1_Pct, tradePnL)))
         {
            g_ladderStep = 1;
            if(vol > 0.0)
               g_realizedThisTrade += before * (want / vol);
            if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
            {
               ResetPosState();
               return;
            }
         }
      }
   }

   if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
      return;

   tradePnL = TradeProfitMoney(profit);
   tradePct = 100.0 * tradePnL / cap;

   if(g_ladderStep == 1 && tradePct >= InpLadder2_Pct)
   {
      double want = RoundDownVolume(g_posOpenVol * InpLadder2_CloseFrac);
      if(want <= 0.0 && vol > 0.0)
         want = RoundDownVolume(vol * 0.5);
      want = MathMin(want, vol);
      double remain = vol - want;
      if(remain > 0.0 && remain < vmin)
         want = vol;

      if(want >= vmin - 1e-8)
      {
         double before = profit;
         if(CloseVolume(ticket, want, StringFormat("L2 %.1f%% cap (pnl %.2f)", InpLadder2_Pct, tradePnL)))
         {
            g_ladderStep = 2;
            if(vol > 0.0)
               g_realizedThisTrade += before * (want / vol);
            if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
            {
               ResetPosState();
               return;
            }
         }
      }
   }

   if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
      return;

   tradePnL = TradeProfitMoney(profit);
   tradePct = 100.0 * tradePnL / cap;

   if(InpUseLadder3 && g_ladderStep == 2 && tradePct >= InpLadder3_Pct)
   {
      if(CloseVolume(ticket, vol, StringFormat("L3 %.1f%% cap", InpLadder3_Pct)))
      {
         g_ladderStep = 3;
         ResetPosState();
         return;
      }
   }

   if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
      return;

   if(g_ladderStep < 1 && tradePct >= InpLadder2_Pct)
   {
      PrintFormat("ScalpJPY3: SAFETY close | trade %.1f%% >= L2 e escada L0", tradePct);
      if(CloseVolume(ticket, vol, "SAFETY L2"))
      {
         ResetPosState();
         return;
      }
   }

   if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
      return;

   tradePnL = TradeProfitMoney(profit);
   tradePct = 100.0 * tradePnL / cap;

   double atrPts = ATRPointsRaw();
   double startPts = atrPts * InpSoftStart_ATR;
   double lockPts  = atrPts * InpSoftLock_ATR;
   double trailPts = atrPts * InpTrail_ATR;
   if(g_ladderStep >= 2)
   {
      trailPts *= InpSoftTightenAfter2;
      lockPts  *= InpSoftTightenAfter2;
      startPts *= InpSoftTightenAfter2;
   }
   else if(g_ladderStep >= 1)
   {
      trailPts *= InpSoftTightenAfter1;
      lockPts  *= InpSoftTightenAfter1;
      startPts *= InpSoftTightenAfter1;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double newSL = sl;

   if(type == POSITION_TYPE_BUY)
   {
      double profitPts = (bid - open) / _Point;
      if(profitPts >= startPts)
      {
         double lockSL = open + lockPts * _Point;
         double trailSL = bid - trailPts * _Point;
         newSL = MathMax(lockSL, trailSL);
         if(sl > 0.0) newSL = MathMax(newSL, sl);
         if(g_ladderStep >= 1)
            newSL = MathMax(newSL, open + MinStopDistancePoints() * _Point);
         NormalizeSL(POSITION_TYPE_BUY, bid, newSL);
      }
   }
   else
   {
      double profitPts = (open - ask) / _Point;
      if(profitPts >= startPts)
      {
         double lockSL = open - lockPts * _Point;
         double trailSL = ask + trailPts * _Point;
         newSL = MathMin(lockSL, trailSL);
         if(sl > 0.0) newSL = MathMin(newSL, sl);
         if(g_ladderStep >= 1)
            newSL = MathMin(newSL, open - MinStopDistancePoints() * _Point);
         NormalizeSL(POSITION_TYPE_SELL, ask, newSL);
      }
   }

   if(newSL > 0.0 && MathAbs(newSL - sl) >= _Point)
   {
      trade.SetExpertMagicNumber(InpMagic);
      trade.SetDeviationInPoints(InpSlippagePoints);
      trade.SetTypeFillingBySymbol(_Symbol);
      if(!trade.PositionModify(ticket, newSL, 0.0))
         PrintFormat("ScalpJPY3: softlock falhou ret=%u %s", trade.ResultRetcode(), trade.ResultComment());
      else if(InpVerboseLog)
         PrintFormat("ScalpJPY3: SOFT+ SL %.3f -> %.3f | L%d | pnl=%.2f (%.1f%%)",
                     sl, newSL, g_ladderStep, tradePnL, tradePct);
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
         PrintFormat("ScalpJPY3: close falhou ticket=%I64u ret=%u (%s)",
                     ticket, trade.ResultRetcode(), reason);
   }
   ResetPosState();
}

//+------------------------------------------------------------------+
void UpdateChartComment()
{
   string status;
   if(g_dayStopped)
      status = StringFormat("STOP DIA %.0f%%", InpDailyLossPercent);
   else if(g_dayWinMeta)
      status = StringFormat("META DIA %.0f%%", InpDailyWinPercent);
   else
      status = SessionStatusText(TimeTradeServer());

   string skip = (g_lastSkipReason != "" ? "\nskip: " + g_lastSkipReason : "");
   string txt = StringFormat(
      "ScalpUSDJPY v3.01 | %s\ncap %.0f | dayPnL %.2f | meta %.2f | spread %d | L%d | %s%s",
      _Symbol,
      GetCapital(),
      DayPnLMoney(),
      DailyWinTargetMoney(),
      CurrentSpreadPoints(),
      g_ladderStep,
      status,
      skip
   );
   Comment(txt);
}

//+------------------------------------------------------------------+
int OnInit()
{
   string s = _Symbol;
   StringToUpper(s);
   if(StringFind(s, "USDJPY") < 0)
      Print("ScalpJPY3: aviso - símbolo não parece USDJPY: ", _Symbol);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   hEMA50  = iMA(_Symbol, InpTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200 = iMA(_Symbol, InpTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hADX    = iADX(_Symbol, InpTF, InpADXPeriod);
   hATR    = iATR(_Symbol, InpTF, InpATRPeriod);
   hVol    = iVolumes(_Symbol, InpTF, VOLUME_TICK);

   if(hEMA50 == INVALID_HANDLE || hEMA200 == INVALID_HANDLE ||
      hADX == INVALID_HANDLE || hATR == INVALID_HANDLE ||
      (InpUseVolumeFilter && hVol == INVALID_HANDLE))
   {
      Print("ScalpJPY3: falha indicadores");
      return INIT_FAILED;
   }

   ResetDayIfNeeded();
   SyncPosStateFromMarket();

   if(DailyLossHit())
   {
      g_dayStopped = true;
      PrintFormat("ScalpJPY3: STOP DIA já ativo | dayPnL=%.2f | limite=%.2f",
                  DayPnLMoney(), DailyLossLimitMoney());
   }
   else if(DailyWinHit())
   {
      g_dayWinMeta = true;
      PrintFormat("ScalpJPY3: META DIA já ativa | dayPnL=%.2f | meta=%.2f",
                  DayPnLMoney(), DailyWinTargetMoney());
   }

   PrintFormat("ScalpUSDJPY_v3.01 init | %s | capital=%.2f | magic=%I64d | risk=%.2f%% | maxLots=%.2f",
               _Symbol, GetCapital(), InpMagic, InpRiskPercent, InpMaxLots);
   PrintFormat("sessao %02d:%02d-%02d:%02d flat %02d:%02d | dias=%s | break=%d ADX>=%.1f body>=%.2fxATR | volFiltro=%s",
               InpSessStartH, InpSessStartM, InpSessEndH, InpSessEndM,
               InpFlatH, InpFlatM,
               (InpWeekdaysOnly ? "seg-sex" : "todos"),
               InpBreakN, InpAdxGate, InpBodyMin,
               (InpUseVolumeFilter ? "sim" : "nao"));
   PrintFormat("escada: %.1f%%→%.0f%% | %.1f%%→+%.0f%% | L3=%s | SL %.2fxATR teto %.1f%% | stopDia=%.1f%% | metaDia=%.1f%% (%s)",
               InpLadder1_Pct, InpLadder1_CloseFrac * 100.0,
               InpLadder2_Pct, InpLadder2_CloseFrac * 100.0,
               (InpUseLadder3 ? "sim" : "nao/softlock"),
               InpSL_ATR_Mult, InpMaxSL_CapitalPct,
               InpDailyLossPercent, InpDailyWinPercent,
               (InpUseDailyWinMeta ? "on" : "off"));
   PrintFormat("metaDia=só bloqueia entradas | sem teto trades/dia | softLock arm=%.2fxATR | verbose=%s",
               InpSoftStart_ATR, (InpVerboseLog ? "on" : "off"));
   PrintFormat("ScalpJPY3: status agora=%s | server=%s | tradeTerminal=%s | tradeMQL=%s",
               SessionStatusText(TimeTradeServer()),
               TimeToString(TimeTradeServer(), TIME_DATE|TIME_MINUTES),
               (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ? "on" : "OFF"),
               (MQLInfoInteger(MQL_TRADE_ALLOWED) ? "on" : "OFF"));
   UpdateChartComment();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   if(hEMA50  != INVALID_HANDLE) IndicatorRelease(hEMA50);
   if(hEMA200 != INVALID_HANDLE) IndicatorRelease(hEMA200);
   if(hADX    != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hATR    != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hVol    != INVALID_HANDLE) IndicatorRelease(hVol);
}

//+------------------------------------------------------------------+
void OnTick()
{
   ResetDayIfNeeded();
   UpdateChartComment();

   datetime now = TimeTradeServer();

   // Esses returns eram SILENCIOSOS — Comment mostrava SESSÃO mas Experts ficava mudo
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      static datetime lastLogTerm = 0;
      if(now - lastLogTerm >= 60)
      {
         lastLogTerm = now;
         Print("ScalpJPY3: BLOCK | botão AlgoTrading do terminal OFF");
      }
      return;
   }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      static datetime lastLogMql = 0;
      if(now - lastLogMql >= 60)
      {
         lastLogMql = now;
         Print("ScalpJPY3: BLOCK | desmarque/marque 'Permite trading ao vivo' nas propriedades do EA (Aba Comum)");
      }
      return;
   }

   // META DIA / STOP DIA: escada continua (exceto se flat forçado no STOP)
   if(CountOurPositions() > 0 && !ShouldFlat(now) && !g_dayStopped)
      ManageLadderAndSoftLock();

   if(ShouldFlat(now))
   {
      if(CountOurPositions() > 0)
         CloseAllOurs(InpWeekdaysOnly && !IsWeekday(now) ? "flat_weekend" : "flat_swap");
      return;
   }

   if(DailyLossHit() || g_dayStopped)
   {
      g_dayStopped = true;
      if(!g_loggedDailyFlat)
      {
         PrintFormat("ScalpJPY3: STOP DIÁRIO %.1f%% | dayPnL=%.2f | limite=%.2f → sem novas entradas",
                     InpDailyLossPercent, DayPnLMoney(), DailyLossLimitMoney());
         g_loggedDailyFlat = true;
      }
      if(InpFlatOnDailyLoss && CountOurPositions() > 0)
         CloseAllOurs("daily_loss");
      return;
   }

   if(DailyWinHit() || g_dayWinMeta)
   {
      g_dayWinMeta = true;
      if(!g_loggedDailyWin)
      {
         PrintFormat("ScalpJPY3: META DIA %.1f%% | dayPnL=%.2f | meta=%.2f → sem novas entradas (posição segue)",
                     InpDailyWinPercent, DayPnLMoney(), DailyWinTargetMoney());
         g_loggedDailyWin = true;
      }
      return;
   }

   datetime barTime = iTime(_Symbol, InpTF, 1);
   if(barTime == 0 || barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;

   if(!SessionOpen(now))
   {
      if(InpWeekdaysOnly && !IsWeekday(now))
         LogSkip("fim de semana (só seg-sex)");
      else
         LogSkip(StringFormat("fora da sessão %02d:%02d-%02d:%02d (server %s)",
                              InpSessStartH, InpSessStartM, InpSessEndH, InpSessEndM,
                              TimeToString(now, TIME_MINUTES)));
      return;
   }

   if(InpVerboseLog)
      PrintFormat("ScalpJPY3: barra M5 %s | avaliando entrada | spread=%d",
                  TimeToString(barTime, TIME_DATE|TIME_MINUTES), CurrentSpreadPoints());

   if(CountOurPositions() >= InpMaxPositions)
   {
      LogSkip(StringFormat("posição aberta (%d)", CountOurPositions()));
      return;
   }

   int dir = 0;
   if(!GetSignal(dir) || dir == 0)
      return;

   OpenTrade(dir);
}

//+------------------------------------------------------------------+
