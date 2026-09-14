//+------------------------------------------------------------------+
//| TrendWIN_v1.mq5                                                   |
//| Daytrade WIN$ (Clear/MT5) - EMA50/200 + ADX + soft lock           |
//| Volume automático conforme capital (padrão: 1 mini / R$ 1.000)    |
//| v1.11: flat no stop diário, filtro de spread, stops level         |
//+------------------------------------------------------------------+
#property copyright "Vitor / Nomo-MT5 line"
#property version   "1.11"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_WIN_SIZING
{
   SIZING_BY_CAPITAL = 0,  // 1 contrato a cada X reais de capital
   SIZING_FIXED      = 1   // Volume fixo (manual)
};

//------------------------ Inputs ------------------------------------
input group "=== Volume automático ==="
input ENUM_WIN_SIZING InpSizingMode      = SIZING_BY_CAPITAL;
input double InpCapitalPerContract = 1000.0; // 1 mini a cada R$ 1.000
input double InpFallbackCapital  = 1000.0;   // Se MT5 mostrar saldo 0 (Clear)
input double InpFixedVolume      = 1.0;      // Só se Sizing = Fixed
input double InpMaxVolume        = 5.0;      // Teto de segurança
input double InpMinCapitalTrade  = 800.0;    // Abaixo disso não opera

input group "=== Risco diário ==="
input double InpDailyLossPercent = 5.0;      // Para o dia se prejuízo >= X% do capital
input bool   InpFlatOnDailyLoss  = true;     // Zera posição ao bater o stop diário
input int    InpMaxTradesDay     = 4;        // Máx. entradas no dia
input int    InpMaxPositions     = 1;        // Só 1 posição
input int    InpMaxSpreadPoints  = 80;       // Spread máx. (WIN costuma ser baixo; abre largo)

input group "=== Sessão (horário do servidor MT5) ==="
input int    InpStartHour       = 10;      // Clear costuma ser BRT
input int    InpStartMinute     = 15;
input int    InpEndHour         = 16;
input int    InpEndMinute       = 45;
input int    InpFlatHour        = 17;      // Zera posição daytrade
input int    InpFlatMinute      = 0;

input group "=== Tendência ==="
input int    InpEMAFast         = 50;
input int    InpEMASlow         = 200;
input int    InpADXPeriod       = 14;
input double InpADXMin          = 25.0;
input ENUM_TIMEFRAMES InpTF     = PERIOD_M5;

input group "=== Stop / Soft lock (pontos do WIN) ==="
input double InpSL_ATR_Mult     = 1.5;     // SL inicial = ATR * mult
input int    InpATRPeriod       = 14;
input double InpSoftStart_ATR   = 0.70;    // Começa a travar lucro após X ATR
input double InpSoftLock_ATR    = 0.25;    // Trava pelo menos Y ATR de lucro
input double InpTrail_ATR       = 0.50;    // Trail subsequente
input int    InpMinSL_Points    = 150;     // SL mínimo em pontos
input int    InpMaxSL_Points    = 500;     // SL máximo em pontos

input group "=== Geral ==="
input long   InpMagic           = 260914;
input int    InpSlippagePoints  = 30;
input string InpTradeComment    = "TrendWIN_v1";
input bool   InpVerboseLog      = true;

//------------------------ Estado ------------------------------------
datetime g_dayStart = 0;
double   g_dayStartEquity = 0.0;
int      g_tradesToday = 0;
datetime g_lastBarTime = 0;
bool     g_dayStopped = false;
bool     g_loggedDailyFlat = false;

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
// Soma lucro já realizado deste magic neste símbolo (útil se Clear zerar o saldo)
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
// Capital efetivo: tenta ler a conta; se Clear zerar o MT5, usa fallback + PnL do EA.
double GetCapital()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double detected = MathMax(equity, MathMax(balance, free));
   if(detected > 1.0)
      return detected;

   double cap = InpFallbackCapital + RealizedPnLAllTime();
   // soma floating atual
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      cap += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return MathMax(0.0, cap);
}

//+------------------------------------------------------------------+
double DailyLossLimitMoney()
{
   double base = (g_dayStartEquity > 0.0 ? g_dayStartEquity : GetCapital());
   return base * MathAbs(InpDailyLossPercent) / 100.0;
}

//+------------------------------------------------------------------+
// Volume: 1 contrato a cada InpCapitalPerContract (ex.: R$1000 -> 1, R$2000 -> 2)
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
   if(raw < 1.0) raw = 1.0; // com capital mínimo já opera 1

   // Respeita margem livre estimada (quando a Clear reporta)
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
      g_tradesToday = 0;
      g_dayStopped = false;
      g_loggedDailyFlat = false;
      PrintFormat("TrendWIN: novo dia | capital=R$%.2f | vol≈%.0f | stopDia=R$%.2f",
                  g_dayStartEquity, CalcVolume(), DailyLossLimitMoney());
   }
}

//+------------------------------------------------------------------+
double DayPnLMoney()
{
   // Soma deals do magic no dia (mais confiável que equity na Clear)
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

   // Inclui floating da posição atual do magic
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
bool GetSignal(int &dir)
{
   dir = 0;
   double ema50, ema200, adx, plusDI, minusDI, close1;
   if(!Copy1(hEMA50, 0, ema50)) return false;
   if(!Copy1(hEMA200, 0, ema200)) return false;
   if(!Copy1(hADX, 0, adx)) return false;
   if(!Copy1(hADX, 1, plusDI)) return false;
   if(!Copy1(hADX, 2, minusDI)) return false;

   double closes[];
   if(CopyClose(_Symbol, InpTF, 1, 1, closes) != 1)
      return false;
   close1 = closes[0];

   if(adx < InpADXMin)
      return true; // sem sinal, mas dados ok

   bool bull = (close1 > ema50 && close1 > ema200 && ema50 > ema200 && plusDI > minusDI);
   bool bear = (close1 < ema50 && close1 < ema200 && ema50 < ema200 && minusDI > plusDI);

   if(bull) dir = 1;
   else if(bear) dir = -1;
   return true;
}

//+------------------------------------------------------------------+
// ATR bruto em pontos (sem clamp). SL final é limitado em OpenTrade.
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
bool OpenTrade(const int dir)
{
   double vol = CalcVolume();
   if(vol <= 0.0)
   {
      PrintFormat("TrendWIN: sem volume (capital=R$%.2f)", GetCapital());
      return false;
   }

   int spread = CurrentSpreadPoints();
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints)
   {
      if(InpVerboseLog)
         PrintFormat("TrendWIN: skip spread %d > %d", spread, InpMaxSpreadPoints);
      return false;
   }

   double atrPts = ATRPointsRaw();
   double slDist = ClampSLPoints(atrPts * InpSL_ATR_Mult);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
   {
      Print("TrendWIN: sem cotação (pregão fechado?)");
      return false;
   }

   double sl = 0.0;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool ok = false;
   if(dir > 0)
   {
      sl = ask - slDist * _Point;
      NormalizeSL(ORDER_TYPE_BUY, ask, sl);
      ok = trade.Buy(vol, _Symbol, ask, sl, 0.0, InpTradeComment);
   }
   else
   {
      sl = bid + slDist * _Point;
      NormalizeSL(ORDER_TYPE_SELL, bid, sl);
      ok = trade.Sell(vol, _Symbol, bid, sl, 0.0, InpTradeComment);
   }

   if(ok)
   {
      g_tradesToday++;
      PrintFormat("TrendWIN: %s vol=%.0f SL_pts=%.0f spread=%d",
                  (dir > 0 ? "BUY" : "SELL"), vol, slDist, spread);
   }
   else
      PrintFormat("TrendWIN: falha ordem retcode=%u %s", trade.ResultRetcode(), trade.ResultComment());

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
         if(!trade.PositionModify(ticket, newSL, 0.0))
            PrintFormat("TrendWIN: softlock falhou %u", trade.ResultRetcode());
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
         PrintFormat("TrendWIN: close falhou ticket=%I64u ret=%u (%s)",
                     ticket, trade.ResultRetcode(), reason);
   }
}

//+------------------------------------------------------------------+
void UpdateChartComment()
{
   string txt = StringFormat(
      "TrendWIN v1.11 | %s\ncapital R$%.0f | vol≈%.0f | dayPnL R$%.0f\ntrades %d/%d | spread %d | %s",
      _Symbol,
      GetCapital(),
      CalcVolume(),
      DayPnLMoney(),
      g_tradesToday,
      InpMaxTradesDay,
      CurrentSpreadPoints(),
      (g_dayStopped ? "STOP DIA" : (SessionOpen(TimeTradeServer()) ? "SESSÃO" : "FORA"))
   );
   Comment(txt);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(!IsWinSymbol())
      Print("TrendWIN: aviso - símbolo atual não parece WIN: ", _Symbol);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   hEMA50  = iMA(_Symbol, InpTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200 = iMA(_Symbol, InpTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hADX    = iADX(_Symbol, InpTF, InpADXPeriod);
   hATR    = iATR(_Symbol, InpTF, InpATRPeriod);

   if(hEMA50 == INVALID_HANDLE || hEMA200 == INVALID_HANDLE ||
      hADX == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("TrendWIN: falha ao criar indicadores");
      return INIT_FAILED;
   }

   ResetDayIfNeeded();
   PrintFormat("TrendWIN_v1.11 init | %s | capital=R$%.2f | vol=%.0f | stopDia=%.1f%% (R$%.0f) | magic=%I64d",
               _Symbol, GetCapital(), CalcVolume(), InpDailyLossPercent, DailyLossLimitMoney(), InpMagic);
   PrintFormat("softLock arm=%.2fxATR lock=%.2fxATR trail=%.2fxATR | maxSpread=%d | flatOnDaily=%s",
               InpSoftStart_ATR, InpSoftLock_ATR, InpTrail_ATR, InpMaxSpreadPoints,
               (InpFlatOnDailyLoss ? "sim" : "nao"));
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

   // Soft lock sempre que houver posição (exceto se já estamos flatando)
   if(CountOurPositions() > 0 && !ShouldFlat(now) && !g_dayStopped)
      ManageSoftLock();

   // Daytrade: zera no flat hour
   if(ShouldFlat(now))
   {
      if(CountOurPositions() > 0)
         CloseAllOurs("flat_hour");
      return;
   }

   // Stop diário: opcionalmente zera e trava novas entradas
   if(DailyLossHit() || g_dayStopped)
   {
      g_dayStopped = true;
      if(InpFlatOnDailyLoss && CountOurPositions() > 0)
      {
         if(!g_loggedDailyFlat)
         {
            PrintFormat("TrendWIN: STOP DIÁRIO | dayPnL=R$%.2f | limite=R$%.2f → flat",
                        DayPnLMoney(), DailyLossLimitMoney());
            g_loggedDailyFlat = true;
         }
         CloseAllOurs("daily_loss");
      }
      return;
   }

   if(!SessionOpen(now))
      return;

   // Só avalia quando a barra M5 anterior fecha (sinal no candle 1)
   datetime barTime = iTime(_Symbol, InpTF, 1);
   if(barTime == 0 || barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;

   if(CountOurPositions() >= InpMaxPositions)
      return;
   if(g_tradesToday >= InpMaxTradesDay)
      return;

   int dir = 0;
   if(!GetSignal(dir) || dir == 0)
      return;

   OpenTrade(dir);
}

//+------------------------------------------------------------------+
