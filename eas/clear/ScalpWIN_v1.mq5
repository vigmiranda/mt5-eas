//+------------------------------------------------------------------+
//| ScalpWIN_v1.mq5                                                   |
//| Daytrade WIN (Clear/MT5) - scalp por rompimento + TP + soft lock  |
//| Volume automático: 1 mini / R$ 1.000 | várias entradas no dia     |
//| Gráfico: WINV26 (ou WIN$) M5                                      |
//| v1.02: capital manual/Clear + logs detalhados de skip             |
//+------------------------------------------------------------------+
#property copyright "Vitor / mt5-eas"
#property version   "1.02"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_WIN_SIZING
{
   SIZING_BY_CAPITAL = 0,  // 1 contrato a cada X reais de capital
   SIZING_FIXED      = 1   // Volume fixo (manual)
};

enum ENUM_CAPITAL_MODE
{
   CAPITAL_AUTO   = 0,  // Usa saldo Clear se confiável; senão fallback
   CAPITAL_MANUAL = 1,  // Usa InpManualCapital (recomendado na Clear)
   CAPITAL_BROKER = 2   // Força equity/balance/free do MT5
};

//------------------------ Inputs ------------------------------------
input group "=== Volume / capital ==="
input ENUM_WIN_SIZING InpSizingMode      = SIZING_BY_CAPITAL;
input ENUM_CAPITAL_MODE InpCapitalMode   = CAPITAL_MANUAL; // Clear: use Manual
input double InpManualCapital    = 1000.0;   // Capital real alocado no daytrade (Clear)
input double InpCapitalPerContract = 1000.0; // 1 mini a cada R$ 1.000
input double InpFallbackCapital  = 1000.0;   // Se Auto e MT5 não reportar saldo
input double InpBrokerMinReliable = 50.0;    // Abaixo disso Auto ignora saldo MT5
input double InpFixedVolume      = 1.0;      // Só se Sizing = Fixed
input double InpMaxVolume        = 5.0;      // Teto de segurança
input double InpMinCapitalTrade  = 800.0;    // Abaixo disso não opera

input group "=== Risco diário ==="
input double InpDailyLossPercent = 4.0;      // Para o dia se prejuízo >= X% do capital
input bool   InpFlatOnDailyLoss  = true;     // Zera posição ao bater o stop diário
input int    InpMaxTradesDay     = 15;       // Máx. entradas no dia (scalp)
input int    InpMaxPositions     = 1;        // Só 1 posição
input int    InpMaxSpreadPoints  = 40;       // Spread máx. (WIN líquido costuma ser baixo)

input group "=== Sessão (horário do servidor MT5) ==="
input int    InpStartHour       = 10;      // Clear costuma ser BRT
input int    InpStartMinute     = 15;
input int    InpEndHour         = 16;
input int    InpEndMinute       = 45;
input int    InpFlatHour        = 17;      // Zera posição daytrade
input int    InpFlatMinute      = 0;

input group "=== Entrada (rompimento) ==="
input int    InpBreakBars       = 3;       // Rompe máx/mín das N barras anteriores
input int    InpEMAFast         = 50;
input int    InpEMASlow         = 200;
input bool   InpUseEmaTrend     = true;    // BUY só EMA50>EMA200; SELL inverso
input int    InpADXPeriod       = 14;
input double InpADXMin          = 20.0;    // ADX mínimo (um pouco mais frouxo que trend)
input bool   InpUseADXFilter    = true;
input double InpMinBodyATR      = 0.35;    // Corpo mínimo do candle = fator * ATR
input ENUM_TIMEFRAMES InpTF     = PERIOD_M5;

input group "=== Stop / TP / Soft lock (pontos do WIN) ==="
input double InpSL_ATR_Mult     = 1.20;    // SL inicial = ATR * mult
input int    InpATRPeriod       = 14;
input bool   InpUseTP           = true;    // Take profit fixo (além do soft lock)
input double InpTP_ATR_Mult     = 2.00;    // TP = ATR * mult (margem boa no WIN)
input int    InpMinTP_Points    = 200;     // TP mínimo em pontos
input int    InpMaxTP_Points    = 600;     // TP máximo em pontos
input double InpSoftStart_ATR   = 0.70;    // Arma soft lock após X ATR (deixa o TP trabalhar)
input double InpSoftLock_ATR    = 0.25;    // Trava pelo menos Y ATR de lucro
input double InpTrail_ATR       = 0.45;    // Trail subsequente
input int    InpMinSL_Points    = 100;     // SL mínimo em pontos
input int    InpMaxSL_Points    = 350;     // SL máximo em pontos

input group "=== Geral ==="
input long   InpMagic           = 260916;
input int    InpSlippagePoints  = 30;
input string InpTradeComment    = "ScalpWIN_v1";
input bool   InpVerboseLog      = true;    // Loga motivo de cada barra sem entrada

//------------------------ Estado ------------------------------------
datetime g_dayStart = 0;
double   g_dayStartEquity = 0.0;
int      g_tradesToday = 0;
datetime g_lastBarTime = 0;
bool     g_dayStopped = false;
bool     g_loggedDailyFlat = false;
string   g_capitalSource = "n/a";
string   g_lastSkipReason = "";

int hEMA50 = INVALID_HANDLE;
int hEMA200 = INVALID_HANDLE;
int hADX = INVALID_HANDLE;
int hATR = INVALID_HANDLE;

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
   if(spr > 0)
      return (int)spr;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0 || _Point <= 0.0)
      return 0;
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
double RealizedPnLAllTime()
{
   if(!HistorySelect(0, TimeTradeServer() + 1))
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
   return pnl;
}

//+------------------------------------------------------------------+
void LogAccountSnapshot()
{
   PrintFormat("ScalpWIN: conta MT5 | balance=R$%.2f equity=R$%.2f free=R$%.2f margin=R$%.2f credit=R$%.2f",
               AccountInfoDouble(ACCOUNT_BALANCE),
               AccountInfoDouble(ACCOUNT_EQUITY),
               AccountInfoDouble(ACCOUNT_MARGIN_FREE),
               AccountInfoDouble(ACCOUNT_MARGIN),
               AccountInfoDouble(ACCOUNT_CREDIT));
}

//+------------------------------------------------------------------+
double BrokerReportedCapital()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   return MathMax(equity, MathMax(balance, free));
}

//+------------------------------------------------------------------+
// Capital operacional: na Clear o MT5 costuma zerar saldo — use Manual.
double GetCapital()
{
   if(InpCapitalMode == CAPITAL_MANUAL && InpManualCapital > 0.0)
   {
      g_capitalSource = "manual";
      return InpManualCapital;
   }

   double broker = BrokerReportedCapital();
   if(InpCapitalMode == CAPITAL_BROKER)
   {
      g_capitalSource = "broker";
      return MathMax(0.0, broker);
   }

   // AUTO
   if(broker >= InpBrokerMinReliable)
   {
      g_capitalSource = "broker";
      return broker;
   }

   double cap = InpFallbackCapital + RealizedPnLAllTime();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      cap += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   g_capitalSource = "fallback";
   return MathMax(0.0, cap);
}

//+------------------------------------------------------------------+
int CountEntriesToday()
{
   if(g_dayStart <= 0)
      return 0;
   if(!HistorySelect(g_dayStart, TimeTradeServer() + 1))
      return 0;

   int n = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
void LogSkip(const string reason)
{
   g_lastSkipReason = reason;
   if(InpVerboseLog)
      PrintFormat("ScalpWIN: SKIP | %s", reason);
}

//+------------------------------------------------------------------+
double DailyLossLimitMoney()
{
   double base = (g_dayStartEquity > 0.0 ? g_dayStartEquity : GetCapital());
   return base * MathAbs(InpDailyLossPercent) / 100.0;
}

//+------------------------------------------------------------------+
double CalcVolume()
{
   if(InpSizingMode == SIZING_FIXED)
      return ClampVolume(InpFixedVolume);

   double capital = GetCapital();
   if(capital < InpMinCapitalTrade)
      return 0.0;

   double per = InpCapitalPerContract;
   if(per <= 0.0) per = 1000.0;

   double raw = MathFloor(capital / per + 1e-8);
   if(raw < 1.0) raw = 1.0;

   double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(free > 1.0)
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
bool IsWinSymbol()
{
   string s = _Symbol;
   StringToUpper(s);
   return (StringFind(s, "WIN") >= 0);
}

//+------------------------------------------------------------------+
bool SessionOpen(const datetime now)
{
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int nowMin = dt.hour * 60 + dt.min;
   int startMin = InpStartHour * 60 + InpStartMinute;
   int endMin = InpEndHour * 60 + InpEndMinute;
   return (nowMin >= startMin && nowMin < endMin);
}

//+------------------------------------------------------------------+
bool ShouldFlat(const datetime now)
{
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int nowMin = dt.hour * 60 + dt.min;
   int flatMin = InpFlatHour * 60 + InpFlatMinute;
   return (nowMin >= flatMin);
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
      g_tradesToday = CountEntriesToday();
      g_dayStopped = false;
      g_loggedDailyFlat = false;
      g_lastSkipReason = "";
      PrintFormat("ScalpWIN: novo dia | capital=R$%.2f (%s) | vol≈%.0f | stopDia=R$%.2f | entradasHoje=%d",
                  g_dayStartEquity, g_capitalSource, CalcVolume(), DailyLossLimitMoney(), g_tradesToday);
   }
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
bool Copy1(const int handle, const int buffer, double &out)
{
   double a[];
   if(CopyBuffer(handle, buffer, 1, 1, a) != 1)
      return false;
   out = a[0];
   return true;
}

//+------------------------------------------------------------------+
double ATRPointsRaw()
{
   double atr = 0.0;
   if(!Copy1(hATR, 0, atr) || atr <= 0.0)
      return (double)InpMinSL_Points;
   double pt = _Point;
   if(pt <= 0.0) pt = 1.0;
   return atr / pt;
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
double ClampTPPoints(const double pts)
{
   double out = pts;
   if(out < InpMinTP_Points) out = InpMinTP_Points;
   if(out > InpMaxTP_Points) out = InpMaxTP_Points;
   return out;
}

//+------------------------------------------------------------------+
bool NormalizeSL(const long type, const double price, double &sl)
{
   if(sl <= 0.0 || price <= 0.0 || _Point <= 0.0)
      return false;

   int need = MinStopDistancePoints();
   double minDist = need * _Point;

   if(type == POSITION_TYPE_BUY || type == ORDER_TYPE_BUY)
   {
      if(price - sl < minDist)
         sl = price - minDist;
   }
   else
   {
      if(sl - price < minDist)
         sl = price + minDist;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   return true;
}

//+------------------------------------------------------------------+
bool NormalizeTP(const long type, const double price, double &tp)
{
   if(tp <= 0.0 || price <= 0.0 || _Point <= 0.0)
      return false;

   int need = MinStopDistancePoints();
   double minDist = need * _Point;

   if(type == POSITION_TYPE_BUY || type == ORDER_TYPE_BUY)
   {
      if(tp - price < minDist)
         tp = price + minDist;
   }
   else
   {
      if(price - tp < minDist)
         tp = price - minDist;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   tp = NormalizeDouble(tp, digits);
   return true;
}

//+------------------------------------------------------------------+
// Sinal scalp: candle fechado com corpo + rompimento HH/LL + filtros
bool GetSignal(int &dir)
{
   dir = 0;

   double ema50, ema200, adx, atr;
   if(!Copy1(hEMA50, 0, ema50)) { LogSkip("indicador EMA50 sem dados"); return false; }
   if(!Copy1(hEMA200, 0, ema200)) { LogSkip("indicador EMA200 sem dados"); return false; }
   if(!Copy1(hADX, 0, adx)) { LogSkip("indicador ADX sem dados"); return false; }
   if(!Copy1(hATR, 0, atr) || atr <= 0.0) { LogSkip("indicador ATR sem dados"); return false; }

   if(InpUseADXFilter && adx < InpADXMin)
   {
      LogSkip(StringFormat("ADX fraco %.1f < %.1f", adx, InpADXMin));
      return true;
   }

   double open1  = iOpen(_Symbol, InpTF, 1);
   double close1 = iClose(_Symbol, InpTF, 1);
   if(open1 <= 0.0 || close1 <= 0.0)
   {
      LogSkip("candle 1 sem OHLC");
      return false;
   }

   double body = MathAbs(close1 - open1);
   double minBody = atr * InpMinBodyATR;
   double bodyPts = (_Point > 0.0 ? body / _Point : 0.0);
   double minBodyPts = (_Point > 0.0 ? minBody / _Point : 0.0);
   if(body < minBody)
   {
      LogSkip(StringFormat("corpo fraco %.0f < %.0f pts (ATR)", bodyPts, minBodyPts));
      return true;
   }

   int bars = MathMax(2, InpBreakBars);
   double hh = iHigh(_Symbol, InpTF, 2);
   double ll = iLow(_Symbol, InpTF, 2);
   for(int i = 3; i <= bars; i++)
   {
      hh = MathMax(hh, iHigh(_Symbol, InpTF, i));
      ll = MathMin(ll, iLow(_Symbol, InpTF, i));
   }

   bool bull = (close1 > open1);
   bool bear = (close1 < open1);
   bool upTrend   = (ema50 > ema200);
   bool downTrend = (ema50 < ema200);

   if(bull && close1 > hh)
   {
      if(InpUseEmaTrend && !upTrend)
      {
         LogSkip(StringFormat("rompimento alta mas EMA contra (EMA%d=%.0f <= EMA%d=%.0f)",
                              InpEMAFast, ema50, InpEMASlow, ema200));
         return true;
      }
      dir = 1;
      g_lastSkipReason = "";
      if(InpVerboseLog)
         PrintFormat("ScalpWIN: SINAL BUY | close=%.0f > hh=%.0f | ADX=%.1f | body=%.0fpts",
                     close1, hh, adx, bodyPts);
      return true;
   }

   if(bear && close1 < ll)
   {
      if(InpUseEmaTrend && !downTrend)
      {
         LogSkip(StringFormat("rompimento baixa mas EMA contra (EMA%d=%.0f >= EMA%d=%.0f)",
                              InpEMAFast, ema50, InpEMASlow, ema200));
         return true;
      }
      dir = -1;
      g_lastSkipReason = "";
      if(InpVerboseLog)
         PrintFormat("ScalpWIN: SINAL SELL | close=%.0f < ll=%.0f | ADX=%.1f | body=%.0fpts",
                     close1, ll, adx, bodyPts);
      return true;
   }

   LogSkip(StringFormat("sem rompimento | close=%.0f hh=%.0f ll=%.0f | ADX=%.1f body=%.0fpts | EMA%s",
                        close1, hh, ll, adx, bodyPts,
                        (upTrend ? "alta" : (downTrend ? "baixa" : "flat"))));
   return true;
}

//+------------------------------------------------------------------+
bool OpenTrade(const int dir)
{
   double vol = CalcVolume();
   if(vol <= 0.0)
   {
      LogSkip(StringFormat("sem volume (capital=R$%.2f fonte=%s min=R$%.0f)",
                           GetCapital(), g_capitalSource, InpMinCapitalTrade));
      return false;
   }

   int spread = CurrentSpreadPoints();
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints)
   {
      LogSkip(StringFormat("spread %d > max %d", spread, InpMaxSpreadPoints));
      return false;
   }

   double atrPts = ATRPointsRaw();
   double slDist = ClampSLPoints(atrPts * InpSL_ATR_Mult);
   double tpDist = 0.0;
   if(InpUseTP)
      tpDist = ClampTPPoints(atrPts * InpTP_ATR_Mult);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
   {
      Print("ScalpWIN: sem cotação (pregão fechado?)");
      return false;
   }

   double sl = 0.0;
   double tp = 0.0;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool ok = false;
   if(dir > 0)
   {
      sl = ask - slDist * _Point;
      NormalizeSL(ORDER_TYPE_BUY, ask, sl);
      if(InpUseTP && tpDist > 0.0)
      {
         tp = ask + tpDist * _Point;
         NormalizeTP(ORDER_TYPE_BUY, ask, tp);
      }
      ok = trade.Buy(vol, _Symbol, ask, sl, tp, InpTradeComment);
   }
   else
   {
      sl = bid + slDist * _Point;
      NormalizeSL(ORDER_TYPE_SELL, bid, sl);
      if(InpUseTP && tpDist > 0.0)
      {
         tp = bid - tpDist * _Point;
         NormalizeTP(ORDER_TYPE_SELL, bid, tp);
      }
      ok = trade.Sell(vol, _Symbol, bid, sl, tp, InpTradeComment);
   }

   if(ok)
   {
      g_tradesToday++;
      PrintFormat("ScalpWIN: %s vol=%.0f SL_pts=%.0f TP_pts=%.0f spread=%d trades=%d/%d",
                  (dir > 0 ? "BUY" : "SELL"), vol, slDist, tpDist, spread,
                  g_tradesToday, InpMaxTradesDay);
   }
   else
      PrintFormat("ScalpWIN: falha ordem retcode=%u %s", trade.ResultRetcode(), trade.ResultComment());

   return ok;
}

//+------------------------------------------------------------------+
void ManageSoftLock()
{
   double atrPts = ATRPointsRaw();
   double startPts = atrPts * InpSoftStart_ATR;
   double lockPts  = atrPts * InpSoftLock_ATR;
   double trailPts = atrPts * InpTrail_ATR;

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
      double tp = PositionGetDouble(POSITION_TP); // preserva TP ao trailar
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
            NormalizeSL(POSITION_TYPE_BUY, bid, newSL);
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profitPts = (open - ask) / _Point;
         if(profitPts >= startPts)
         {
            double lockSL = open - lockPts * _Point;
            double trailSL = ask + trailPts * _Point;
            newSL = MathMin(lockSL, trailSL);
            if(sl > 0.0) newSL = MathMin(newSL, sl);
            NormalizeSL(POSITION_TYPE_SELL, ask, newSL);
         }
      }

      if(newSL > 0.0 && MathAbs(newSL - sl) >= _Point)
      {
         if(!trade.PositionModify(ticket, newSL, tp))
            PrintFormat("ScalpWIN: softlock falhou %u", trade.ResultRetcode());
         else if(InpVerboseLog)
            PrintFormat("ScalpWIN: SOFT+ SL %.0f -> %.0f (TP=%.0f)", sl, newSL, tp);
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
         PrintFormat("ScalpWIN: close falhou ticket=%I64u ret=%u (%s)",
                     ticket, trade.ResultRetcode(), reason);
   }
}

//+------------------------------------------------------------------+
void UpdateChartComment()
{
   string status = g_dayStopped ? "STOP DIA (sem novas entradas)"
                  : (SessionOpen(TimeTradeServer()) ? "SESSÃO" : "FORA");
   string skip = (g_lastSkipReason != "" ? "\nultimo skip: " + g_lastSkipReason : "");
   string txt = StringFormat(
      "ScalpWIN v1.02 | %s\ncapital R$%.0f (%s) | vol≈%.0f | dayPnL R$%.0f\ntrades %d/%d | spread %d | TP %s | %s%s",
      _Symbol,
      GetCapital(),
      g_capitalSource,
      CalcVolume(),
      DayPnLMoney(),
      g_tradesToday,
      InpMaxTradesDay,
      CurrentSpreadPoints(),
      (InpUseTP ? StringFormat("%.2fxATR", InpTP_ATR_Mult) : "off"),
      status,
      skip
   );
   Comment(txt);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(!IsWinSymbol())
      Print("ScalpWIN: aviso - símbolo atual não parece WIN: ", _Symbol);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   hEMA50  = iMA(_Symbol, InpTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200 = iMA(_Symbol, InpTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hADX    = iADX(_Symbol, InpTF, InpADXPeriod);
   hATR    = iATR(_Symbol, InpTF, InpATRPeriod);

   if(hEMA50 == INVALID_HANDLE || hEMA200 == INVALID_HANDLE ||
      hADX == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("ScalpWIN: falha ao criar indicadores");
      return INIT_FAILED;
   }

   LogAccountSnapshot();
   ResetDayIfNeeded();
   // Se o EA foi recolocado no mesmo dia, reconstrói contagem e estado do stop
   g_tradesToday = CountEntriesToday();
   if(DailyLossHit())
   {
      g_dayStopped = true;
      PrintFormat("ScalpWIN: STOP DIA já ativo no init | dayPnL=R$%.2f | limite=R$%.2f (sem novas entradas hoje)",
                  DayPnLMoney(), DailyLossLimitMoney());
   }

   PrintFormat("ScalpWIN_v1.02 init | %s | capital=R$%.2f (%s) | vol=%.0f | stopDia=%.1f%% (R$%.0f) | magic=%I64d",
               _Symbol, GetCapital(), g_capitalSource, CalcVolume(),
               InpDailyLossPercent, DailyLossLimitMoney(), InpMagic);
   PrintFormat("modoCapital=%d manual=R$%.0f | brokerRaw=R$%.2f | entradasHoje=%d",
               InpCapitalMode, InpManualCapital, BrokerReportedCapital(), g_tradesToday);
   PrintFormat("rompimento %d barras | body>=%.2fxATR | ADX>=%.1f | SL=%.2fxATR | TP=%s",
               InpBreakBars, InpMinBodyATR, InpADXMin, InpSL_ATR_Mult,
               (InpUseTP ? StringFormat("%.2fxATR (%d-%d pts)", InpTP_ATR_Mult, InpMinTP_Points, InpMaxTP_Points) : "off"));
   PrintFormat("softLock arm=%.2fxATR lock=%.2fxATR trail=%.2fxATR | maxSpread=%d | maxTrades=%d | verbose=%s",
               InpSoftStart_ATR, InpSoftLock_ATR, InpTrail_ATR, InpMaxSpreadPoints, InpMaxTradesDay,
               (InpVerboseLog ? "sim" : "nao"));
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
}

//+------------------------------------------------------------------+
void OnTick()
{
   ResetDayIfNeeded();
   UpdateChartComment();

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return;

   datetime now = TimeTradeServer();

   if(CountOurPositions() > 0 && !ShouldFlat(now) && !g_dayStopped)
      ManageSoftLock();

   if(ShouldFlat(now))
   {
      if(CountOurPositions() > 0)
         CloseAllOurs("flat_hour");
      return;
   }

   if(DailyLossHit() || g_dayStopped)
   {
      g_dayStopped = true;
      if(!g_loggedDailyFlat)
      {
         PrintFormat("ScalpWIN: STOP DIÁRIO ATIVO | dayPnL=R$%.2f | limite=R$%.2f | capitalBase=R$%.2f (%s) → sem novas entradas hoje",
                     DayPnLMoney(), DailyLossLimitMoney(), g_dayStartEquity, g_capitalSource);
         g_loggedDailyFlat = true;
      }
      if(InpFlatOnDailyLoss && CountOurPositions() > 0)
         CloseAllOurs("daily_loss");
      return;
   }

   if(!SessionOpen(now))
      return;

   datetime barTime = iTime(_Symbol, InpTF, 1);
   if(barTime == 0 || barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;

   // Recalibra contagem a cada barra (sobrevive a reload do EA)
   g_tradesToday = CountEntriesToday();

   if(CountOurPositions() >= InpMaxPositions)
   {
      LogSkip(StringFormat("já tem posição aberta (%d/%d)", CountOurPositions(), InpMaxPositions));
      return;
   }
   if(g_tradesToday >= InpMaxTradesDay)
   {
      LogSkip(StringFormat("máx. trades do dia %d/%d", g_tradesToday, InpMaxTradesDay));
      return;
   }

   int dir = 0;
   if(!GetSignal(dir) || dir == 0)
      return;

   OpenTrade(dir);
}

//+------------------------------------------------------------------+
