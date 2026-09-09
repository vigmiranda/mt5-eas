//+------------------------------------------------------------------+
//| TrendEURUSD_v1.mq5                                               |
//| Nomo - trend EURUSD filtrado (EMA50/200 + ADX + SL ATR)          |
//| v1.20: EMA cruzada + ADX + stop/take por ATR + soft lock         |
//| Grafico recomendado: EURUSD M30 (ou H1)                          |
//+------------------------------------------------------------------+
#property copyright "Vitor"
#property version   "1.20"
#property strict

input double InpRiskPercent      = 0.50;  // Risco por trade (% saldo)
input double InpMaxLots          = 1.00;  // Teto de lote
input bool   InpUseFixedLots     = false;
input double InpFixedLots        = 0.01;

//--- entrada / tendencia
input int    InpBreakBars        = 8;     // Rompe max/min dos ultimos N candles
input int    InpEmaFast          = 50;    // EMA rapida (tendencia)
input int    InpEmaSlow          = 200;   // EMA lenta (tendencia)
input bool   InpUseEmaTrend      = true;  // BUY so se EMA50>EMA200; SELL inverso
input int    InpADXPeriod        = 14;
input double InpMinADX           = 22.0;  // ADX minimo (forca da tendencia)
input bool   InpUseADXFilter     = true;
input double InpMinBodyATR       = 0.50;  // Corpo minimo = fator * ATR
input int    InpATRPeriod        = 14;

//--- stops / alvos por ATR (recomendacao: SL 1.5 ATR, alvo ~2x risco)
input double InpStopATRMult      = 1.50;  // SL = ATR * este fator
input double InpRewardRisk       = 2.00;  // TP = SL_dist * R:R
input double InpSoftLockStartATR = 0.45;  // Arma soft lock apos lucro = X * ATR
input double InpSoftLockATR      = 0.15;  // Trava lucro minimo = X * ATR
input double InpTrailStartATR    = 0.90;  // Trailing completo apos X * ATR
input double InpTrailStepATR     = 0.35;  // Degrau trailing (ATR)
input double InpLockATR          = 0.30;  // SL atras do preco (ATR)

input int    InpMaxSpreadPoints  = 40;    // Spread max (normal ~13)
input double InpMinStopSpreadMult= 1.5;   // Bloqueia se stop < 1.5x spread
input int    InpMaxOpenPositions = 2;     // Mais seletivo na v1.20
input int    InpMaxTradesDay     = 6;
input double InpMaxLossDayPct    = 2.0;
input int    InpMagic            = 260828;

input bool   InpCloseBeforeSwap  = false;
input int    InpFlatHour         = 21;
input int    InpFlatMinute       = 50;
input bool   InpVerboseLog       = true;

int emaFastHandle = INVALID_HANDLE;
int emaSlowHandle = INVALID_HANDLE;
int atrHandle     = INVALID_HANDLE;
int adxHandle     = INVALID_HANDLE;
int tradesToday = 0;
double dayStartBalance = 0.0;
int dayStamp = 0;
datetime lastBarChecked = 0;

int OnInit()
{
   emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle     = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   adxHandle     = iADX(_Symbol, PERIOD_CURRENT, InpADXPeriod);
   if(emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE ||
      atrHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE)
      return INIT_FAILED;

   ResetDayIfNeeded();

   int spr = CurrentSpreadPoints();
   Print("TrendEURUSD_v1.20 | ", _Symbol, " ", EnumToString(_Period));
   Print("EMA", InpEmaFast, "/", InpEmaSlow, " | ADX>=", DoubleToString(InpMinADX, 1),
         " | SL=", DoubleToString(InpStopATRMult, 2), "xATR | RR=", DoubleToString(InpRewardRisk, 2));
   Print("softLock=", DoubleToString(InpSoftLockStartATR, 2), "xATR (+",
         DoubleToString(InpSoftLockATR, 2), ") | trail=", DoubleToString(InpTrailStartATR, 2), "xATR");
   Print("maxPos=", InpMaxOpenPositions, " | spread=", spr, " pts | max=", InpMaxSpreadPoints);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(emaFastHandle != INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaSlowHandle != INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
   if(atrHandle != INVALID_HANDLE)     IndicatorRelease(atrHandle);
   if(adxHandle != INVALID_HANDLE)     IndicatorRelease(adxHandle);
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
   if(point <= 0.0)
      return;

   if(spread > InpMaxSpreadPoints)
   {
      if(InpVerboseLog)
         Print("Skip: spread alto ", spread, " > ", InpMaxSpreadPoints);
      return;
   }

   int needBars = MathMax(InpBreakBars, MathMax(InpEmaSlow, MathMax(InpATRPeriod, InpADXPeriod))) + 5;
   if(Bars(_Symbol, PERIOD_CURRENT) < needBars)
      return;

   double emaFast[], emaSlow[], atr[], adx[];
   if(CopyBuffer(emaFastHandle, 0, 1, 3, emaFast) < 3) return;
   if(CopyBuffer(emaSlowHandle, 0, 1, 3, emaSlow) < 3) return;
   if(CopyBuffer(atrHandle, 0, 1, 3, atr) < 3) return;
   if(CopyBuffer(adxHandle, 0, 1, 3, adx) < 3) return; // buffer 0 = ADX main
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(adx, true);

   if(atr[1] <= 0.0)
      return;

   int stopPts = (int)MathRound((atr[1] * InpStopATRMult) / point);
   if(stopPts < 1) stopPts = 1;

   int minStop = (int)MathCeil(spread * InpMinStopSpreadMult);
   if(stopPts < minStop)
   {
      if(InpVerboseLog)
         Print("Skip: stop ATR ", stopPts, " pts < ", minStop, " (1.5x spread)");
      return;
   }

   if(InpUseADXFilter && adx[1] < InpMinADX)
   {
      if(InpVerboseLog)
         Print("Skip: ADX fraco ", DoubleToString(adx[1], 1), " < ", InpMinADX);
      return;
   }

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
   bool upTrend   = (emaFast[1] > emaSlow[1]);
   bool downTrend = (emaFast[1] < emaSlow[1]);

   if(bull && close1 > hh)
   {
      if(InpUseEmaTrend && !upTrend)
      {
         if(InpVerboseLog)
            Print("Skip BUY: EMA", InpEmaFast, " <= EMA", InpEmaSlow);
      }
      else
      {
         Print("SINAL BUY | ADX=", DoubleToString(adx[1], 1),
               " | ATR=", DoubleToString(atr[1] / point, 1), "pts",
               " | SL=", stopPts, "pts | spread=", spread);
         OpenTrade(ORDER_TYPE_BUY, atr[1]);
         return;
      }
   }

   if(bear && close1 < ll)
   {
      if(InpUseEmaTrend && !downTrend)
      {
         if(InpVerboseLog)
            Print("Skip SELL: EMA", InpEmaFast, " >= EMA", InpEmaSlow);
      }
      else
      {
         Print("SINAL SELL | ADX=", DoubleToString(adx[1], 1),
               " | ATR=", DoubleToString(atr[1] / point, 1), "pts",
               " | SL=", stopPts, "pts | spread=", spread);
         OpenTrade(ORDER_TYPE_SELL, atr[1]);
         return;
      }
   }

   if(InpVerboseLog)
      Print("Skip: sem rompimento | close=", close1, " hh=", hh, " ll=", ll,
            " | ADX=", DoubleToString(adx[1], 1));
}

void ManageTrailing()
{
   double atrNow = CurrentATR();
   if(atrNow <= 0.0)
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return;

   int softStartPts = MathMax(1, (int)MathRound((atrNow * InpSoftLockStartATR) / point));
   int softLockPts  = MathMax(1, (int)MathRound((atrNow * InpSoftLockATR) / point));
   int trailStartPts= MathMax(softStartPts + 1, (int)MathRound((atrNow * InpTrailStartATR) / point));
   int trailStepPts = MathMax(1, (int)MathRound((atrNow * InpTrailStepATR) / point));
   int lockPts      = MathMax(1, (int)MathRound((atrNow * InpLockATR) / point));
   int takePtsBase  = MathMax(1, (int)MathRound((atrNow * InpStopATRMult * InpRewardRisk) / point));

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
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double favorMove = (type == POSITION_TYPE_BUY)
                         ? (bid - openPx) / point
                         : (openPx - ask) / point;

      double newSL = sl;
      double newTP = tp;

      if(favorMove >= softStartPts && favorMove < trailStartPts)
      {
         if(type == POSITION_TYPE_BUY)
         {
            double softSL = openPx + softLockPts * point;
            if(softSL > sl + point)
               newSL = softSL;
         }
         else
         {
            double softSL = openPx - softLockPts * point;
            if(sl == 0.0 || softSL < sl - point)
               newSL = softSL;
         }
      }

      if(favorMove >= trailStartPts)
      {
         int steps = (int)MathFloor((favorMove - trailStartPts) / trailStepPts) + 1;

         if(type == POSITION_TYPE_BUY)
         {
            double desiredSL = bid - lockPts * point;
            if(desiredSL > newSL + point)
               newSL = desiredSL;
            double desiredTP = openPx + (takePtsBase + steps * trailStepPts) * point;
            if(desiredTP > tp + point)
               newTP = desiredTP;
         }
         else
         {
            double desiredSL = ask + lockPts * point;
            if(newSL == 0.0 || desiredSL < newSL - point)
               newSL = desiredSL;
            double desiredTP = openPx - (takePtsBase + steps * trailStepPts) * point;
            if(tp == 0.0 || desiredTP < tp - point)
               newTP = desiredTP;
         }
      }

      if(favorMove < softStartPts)
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
      else if(favorMove >= trailStartPts)
         Print("TRAIL ticket=", ticket, " SL ", sl, "->", newSL, " TP ", tp, "->", newTP);
      else
         Print("SOFT ticket=", ticket, " SL ", sl, "->", newSL);
   }
}

double CurrentATR()
{
   double atr[];
   if(CopyBuffer(atrHandle, 0, 0, 2, atr) < 2)
      return 0.0;
   ArraySetAsSeries(atr, true);
   return atr[0];
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

double CalculateLots(const double stopDistPrice)
{
   if(InpUseFixedLots)
      return NormalizeLots(InpFixedLots);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double moneyRisk = balance * (InpRiskPercent / 100.0);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || stopDistPrice <= 0.0)
      return NormalizeLots(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

   double lossPerLot = (stopDistPrice / tickSize) * tickValue;
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
      request.deviation = 30;
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

bool OpenTrade(ENUM_ORDER_TYPE type, const double atrValue)
{
   if(atrValue <= 0.0)
      return false;

   double stopDist = atrValue * InpStopATRMult;
   double takeDist = stopDist * InpRewardRisk;
   double lots = CalculateLots(stopDist);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      return false;

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = type;
   request.price = NormalizeDouble(price, digits);
   request.sl = NormalizeDouble((type == ORDER_TYPE_BUY)
                ? price - stopDist
                : price + stopDist, digits);
   request.tp = NormalizeDouble((type == ORDER_TYPE_BUY)
                ? price + takeDist
                : price - takeDist, digits);
   request.deviation = 30;
   request.magic = InpMagic;
   request.comment = "TrendEURUSD_v1.20";
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
         " SL=", request.sl, " TP=", request.tp,
         " (ATR SL=", DoubleToString(InpStopATRMult, 2), "x RR=", DoubleToString(InpRewardRisk, 2), ")",
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
