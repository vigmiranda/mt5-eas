//+------------------------------------------------------------------+
//| TrendWTIUSD_v1.mq5                                               |
//| Nomo - impulso WTI (petroleo) + trailing SL/TP                   |
//| Spread tipico ~45 pts | preco ~88 (3 casas)                      |
//| v1.10: soft lock antes do trailing completo                      |
//+------------------------------------------------------------------+
#property copyright "Vitor"
#property version   "1.10"
#property strict

input double InpRiskPercent      = 0.50;  // Risco por trade (% saldo)
input double InpMaxLots          = 1.00;  // Teto de lote
input bool   InpUseFixedLots     = false;
input double InpFixedLots        = 0.01;

input int    InpBreakBars        = 8;     // Rompe max/min dos ultimos N candles
input int    InpMaPeriod         = 20;    // EMA (filtro leve)
input bool   InpUseEmaFilter     = true;
input double InpMinBodyATR       = 0.55;  // Corpo minimo = fator * ATR
input int    InpATRPeriod        = 14;

// Calibrado WTIUSD Nomo (spread ~45 pts, point=0.001)
input int    InpStopPoints       = 300;   // SL ~$0.30
input int    InpTakePoints       = 600;   // TP ~$0.60
input int    InpTrailStartPoints = 200;   // Trailing apos ~$0.20 de lucro
input int    InpTrailStepPoints  = 80;    // Degrau trailing ~$0.08
input int    InpLockPoints       = 60;    // SL travado ~$0.06 atras
input int    InpSoftLockStart    = 100;   // Trava lucro minimo (H1)
input int    InpSoftLockPts      = 30;    // SL = entrada + X pts

input int    InpMaxSpreadPoints  = 70;    // Spread max (normal ~45)
input double InpMinStopSpreadMult= 1.5;
input int    InpMaxOpenPositions = 3;
input int    InpMaxTradesDay     = 6;
input double InpMaxLossDayPct    = 2.0;
input int    InpMagic            = 310902;

input bool   InpCloseBeforeSwap  = false; // Ative se quiser flat diario
input int    InpFlatHour         = 21;
input int    InpFlatMinute       = 50;
input bool   InpVerboseLog       = true;

int maHandle  = INVALID_HANDLE;
int atrHandle = INVALID_HANDLE;
int tradesToday = 0;
double dayStartBalance = 0.0;
int dayStamp = 0;
datetime lastBarChecked = 0;

int OnInit()
{
   maHandle  = iMA(_Symbol, PERIOD_CURRENT, InpMaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   if(maHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
      return INIT_FAILED;

   ResetDayIfNeeded();

   int spr = CurrentSpreadPoints();
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   Print("TrendWTIUSD_v1.10 | ", _Symbol, " ", EnumToString(_Period));
   Print("maxPos=", InpMaxOpenPositions, " | spread=", spr, " pts | max=", InpMaxSpreadPoints);
   Print("stop=", InpStopPoints, " | take=", InpTakePoints,
         " | softLock=", InpSoftLockStart, "+", InpSoftLockPts,
         " | trail=", InpTrailStartPoints);
   Print("digits=", SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
         " point=", DoubleToString(point, 8));

   if(InpStopPoints < (int)MathCeil(spr * InpMinStopSpreadMult))
      Print("AVISO: stop curto vs spread. Ajuste InpStopPoints.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(maHandle != INVALID_HANDLE)  IndicatorRelease(maHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
}

void OnTick()
{
   ResetDayIfNeeded();

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return;

   if(InpCloseBeforeSwap && IsFlatWindow())
   {
      CloseOurPositions("flat_window");
      return;
   }

   if(CountOpenPositions() > 0)
      ManageTrailing();

   if(CountOpenPositions() >= InpMaxOpenPositions)
      return;

   if(DayLossReached())
      return;
   if(tradesToday >= InpMaxTradesDay)
      return;

   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(barTime == 0 || barTime == lastBarChecked)
      return;
   lastBarChecked = barTime;

   int spread = CurrentSpreadPoints();
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(spread > InpMaxSpreadPoints)
   {
      if(InpVerboseLog)
         Print("Skip: spread alto ", spread, " > ", InpMaxSpreadPoints);
      return;
   }

   int minStop = (int)MathCeil(spread * InpMinStopSpreadMult);
   if(InpStopPoints < minStop)
   {
      if(InpVerboseLog)
         Print("Skip: stop ", InpStopPoints, " < ", minStop);
      return;
   }

   if(Bars(_Symbol, PERIOD_CURRENT) < MathMax(InpBreakBars, InpATRPeriod) + 5)
      return;

   double ma[], atr[];
   if(CopyBuffer(maHandle, 0, 1, 3, ma) < 3)
      return;
   if(CopyBuffer(atrHandle, 0, 1, 3, atr) < 3)
      return;
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(atr, true);

   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open1  = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double body = MathAbs(close1 - open1);
   double minBody = atr[1] * InpMinBodyATR;

   if(body < minBody)
   {
      if(InpVerboseLog)
         Print("Skip: corpo fraco body=", DoubleToString(body / point, 1),
               " | min=", DoubleToString(minBody / point, 1));
      return;
   }

   double hh = iHigh(_Symbol, PERIOD_CURRENT, 2);
   double ll = iLow(_Symbol, PERIOD_CURRENT, 2);
   for(int i = 3; i <= InpBreakBars; i++)
   {
      hh = MathMax(hh, iHigh(_Symbol, PERIOD_CURRENT, i));
      ll = MathMin(ll, iLow(_Symbol, PERIOD_CURRENT, i));
   }

   bool bull = (close1 > open1);
   bool bear = (close1 < open1);

   if(bull && close1 > hh)
   {
      if(InpUseEmaFilter && close1 < ma[1])
      {
         if(InpVerboseLog)
            Print("Skip BUY: abaixo da EMA", InpMaPeriod);
      }
      else
      {
         Print("SINAL BUY | spread=", spread, " | close=", close1);
         OpenTrade(ORDER_TYPE_BUY);
         return;
      }
   }

   if(bear && close1 < ll)
   {
      if(InpUseEmaFilter && close1 > ma[1])
      {
         if(InpVerboseLog)
            Print("Skip SELL: acima da EMA", InpMaPeriod);
      }
      else
      {
         Print("SINAL SELL | spread=", spread, " | close=", close1);
         OpenTrade(ORDER_TYPE_SELL);
         return;
      }
   }

   if(InpVerboseLog)
      Print("Skip: sem rompimento | close=", close1, " hh=", hh, " ll=", ll);
}

void ManageTrailing()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long   type   = PositionGetInteger(POSITION_TYPE);
      double openPx = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double favorMove = (type == POSITION_TYPE_BUY)
                         ? (bid - openPx) / point
                         : (openPx - ask) / point;

      double newSL = sl;
      double newTP = tp;

      if(favorMove >= InpSoftLockStart && favorMove < InpTrailStartPoints)
      {
         if(type == POSITION_TYPE_BUY)
         {
            double softSL = openPx + InpSoftLockPts * point;
            if(softSL > sl + point)
               newSL = softSL;
         }
         else
         {
            double softSL = openPx - InpSoftLockPts * point;
            if(sl == 0.0 || softSL < sl - point)
               newSL = softSL;
         }
      }

      if(favorMove >= InpTrailStartPoints)
      {
         int steps = (int)MathFloor((favorMove - InpTrailStartPoints) / InpTrailStepPoints) + 1;

         if(type == POSITION_TYPE_BUY)
         {
            double desiredSL = bid - InpLockPoints * point;
            if(desiredSL > newSL + point)
               newSL = desiredSL;
            double desiredTP = openPx + (InpTakePoints + steps * InpTrailStepPoints) * point;
            if(desiredTP > tp + point)
               newTP = desiredTP;
         }
         else
         {
            double desiredSL = ask + InpLockPoints * point;
            if(newSL == 0.0 || desiredSL < newSL - point)
               newSL = desiredSL;
            double desiredTP = openPx - (InpTakePoints + steps * InpTrailStepPoints) * point;
            if(tp == 0.0 || desiredTP < tp - point)
               newTP = desiredTP;
         }
      }

      if(favorMove < InpSoftLockStart)
         continue;

      newSL = NormalizeDouble(newSL, digits);
      newTP = NormalizeDouble(newTP, digits);
      if(MathAbs(newSL - sl) < point && MathAbs(newTP - tp) < point)
         continue;

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);
      request.action   = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol   = _Symbol;
      request.sl       = newSL;
      request.tp       = newTP;
      request.magic    = InpMagic;

      if(!OrderSend(request, result))
         Print("Falha trailing ticket=", ticket, " err=", GetLastError());
      else
         Print("Trailing ticket=", ticket, " SL ", sl, "->", newSL, " TP ", tp, "->", newTP);
   }
}

bool IsFlatWindow()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int mins = now.hour * 60 + now.min;
   return (mins >= InpFlatHour * 60 + InpFlatMinute && mins <= 22 * 60 + 10);
}

int CurrentSpreadPoints()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) return 999999;
   return (int)MathRound((SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / point);
}

double CalculateLots()
{
   if(InpUseFixedLots)
      return NormalizeLots(InpFixedLots);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double moneyRisk = balance * (InpRiskPercent / 100.0);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || InpStopPoints <= 0)
      return NormalizeLots(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

   double lossPerLot = ((InpStopPoints * point) / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return NormalizeLots(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

   return NormalizeLots(MathMin(moneyRisk / lossPerLot, InpMaxLots));
}

double NormalizeLots(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0) stepLot = 0.01;
   lots = MathFloor(lots / stepLot) * stepLot;
   return MathMax(minLot, MathMin(maxLot, lots));
}

bool DayLossReached()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   return ((dayStartBalance - equity) >= dayStartBalance * (InpMaxLossDayPct / 100.0));
}

void ResetDayIfNeeded()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int stamp = now.year * 10000 + now.mon * 100 + now.day;
   if(stamp != dayStamp)
   {
      dayStamp = stamp;
      tradesToday = 0;
      dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("Novo dia. Balance base: ", dayStartBalance);
   }
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      count++;
   }
   return count;
}

void CloseOurPositions(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);
      request.action = TRADE_ACTION_DEAL;
      request.position = ticket;
      request.symbol = _Symbol;
      request.volume = volume;
      request.deviation = 50;
      request.magic = InpMagic;
      request.comment = reason;
      request.type_filling = ResolveFilling();
      if(type == POSITION_TYPE_BUY)
      {
         request.type = ORDER_TYPE_SELL;
         request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      }
      else
      {
         request.type = ORDER_TYPE_BUY;
         request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      }
      if(!OrderSend(request, result))
         Print("Falha flat: ", GetLastError());
   }
}

bool OpenTrade(ENUM_ORDER_TYPE type)
{
   double lots = CalculateLots();
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      return false;

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = type;
   request.price = NormalizeDouble(price, digits);
   request.sl = NormalizeDouble((type == ORDER_TYPE_BUY)
                ? price - InpStopPoints * point
                : price + InpStopPoints * point, digits);
   request.tp = NormalizeDouble((type == ORDER_TYPE_BUY)
                ? price + InpTakePoints * point
                : price - InpTakePoints * point, digits);
   request.deviation = 50;
   request.magic = InpMagic;
   request.comment = "TrendWTIUSD_v1.10";
   request.type_filling = ResolveFilling();

   if(!OrderSend(request, result))
   {
      Print("Falha OrderSend: ", GetLastError(), " ", result.retcode);
      return false;
   }
   if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED)
   {
      Print("Ordem rejeitada: ", result.retcode, " ", result.comment);
      return false;
   }

   tradesToday++;
   Print("ENTROU ", EnumToString(type), " lote=", DoubleToString(lots, 2),
         " abertas=", CountOpenPositions(), "/", InpMaxOpenPositions,
         " spread=", CurrentSpreadPoints());
   return true;
}

ENUM_ORDER_TYPE_FILLING ResolveFilling()
{
   int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}
