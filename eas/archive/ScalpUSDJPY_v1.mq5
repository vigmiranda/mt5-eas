//+------------------------------------------------------------------+
//| ScalpUSDJPY_v1.mq5                                              |
//| Nomo - scalp USDJPY M5 | spread ~21 pts                          |
//| v1.30: trailing em degraus (estilo Trend, passos curtos)         |
//+------------------------------------------------------------------+
#property copyright "Vitor"
#property version   "1.30"
#property strict

input double InpRiskPercent      = 0.50;
input double InpMaxLots          = 1.00;
input bool   InpUseFixedLots     = false;
input double InpFixedLots        = 0.01;

input int    InpFastMaPeriod     = 20;
input int    InpStopPoints       = 160;   // SL inicial (~16 pips)
input int    InpTakePoints       = 100;   // TP inicial (scalp curto)

// Trailing em degraus (como Trend, mas passos menores)
input int    InpSoftLockStart    = 30;    // Com +X pts: trava lucro minimo
input int    InpSoftLockPts      = 10;    // SL = entrada + X pts (lucro minimo)
input int    InpTrailStartPoints = 45;    // A partir daqui: trailing + TP estica
input int    InpTrailStepPoints  = 20;    // A cada +X pts de lucro, sobe SL/TP
input int    InpLockPoints       = 28;    // SL fica X pts atras do preco

input int    InpMaxSpreadPoints  = 35;
input int    InpMaxOpenPositions = 2;
input int    InpMaxTradesDay     = 10;
input double InpMaxLossDayPct    = 2.0;
input int    InpMagic            = 260829;
input bool   InpVerboseLog       = true;

int maHandle = INVALID_HANDLE;
int tradesToday = 0;
double dayStartBalance = 0.0;
int dayStamp = 0;
datetime lastBarChecked = 0;

int OnInit()
{
   maHandle = iMA(_Symbol, PERIOD_CURRENT, InpFastMaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE)
      return INIT_FAILED;

   ResetDayIfNeeded();

   Print("ScalpUSDJPY_v1.30 | ", _Symbol, " ", EnumToString(_Period));
   Print("stop=", InpStopPoints, " tpIni=", InpTakePoints);
   Print("softLock=", InpSoftLockStart, "+", InpSoftLockPts,
         " | trail=", InpTrailStartPoints, " step=", InpTrailStepPoints,
         " lock=", InpLockPoints);
   Print("spread=", CurrentSpreadPoints(), " max=", InpMaxSpreadPoints);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
}

void OnTick()
{
   ResetDayIfNeeded();

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return;

   if(CountOpenPositions() > 0)
      ManageTrailing();

   if(DayLossReached())
      return;
   if(CountOpenPositions() >= InpMaxOpenPositions)
      return;
   if(tradesToday >= InpMaxTradesDay)
      return;

   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(barTime == 0 || barTime == lastBarChecked)
      return;
   lastBarChecked = barTime;

   int spread = CurrentSpreadPoints();
   if(spread > InpMaxSpreadPoints)
   {
      if(InpVerboseLog)
         Print("Skip: spread alto ", spread, " > ", InpMaxSpreadPoints);
      return;
   }

   double ma[];
   if(CopyBuffer(maHandle, 0, 1, 3, ma) < 3)
      return;
   ArraySetAsSeries(ma, true);

   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);

   if(close2 <= ma[2] && close1 > ma[1])
   {
      Print("SINAL BUY scalp JPY | spread=", spread);
      OpenTrade(ORDER_TYPE_BUY);
      return;
   }

   if(close2 >= ma[2] && close1 < ma[1])
   {
      Print("SINAL SELL scalp JPY | spread=", spread);
      OpenTrade(ORDER_TYPE_SELL);
   }
}

// Trailing estilo Trend: sobe SL/TP pouco a pouco conforme o lucro cresce
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
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double favorPts = (type == POSITION_TYPE_BUY)
                        ? (bid - openPx) / point
                        : (openPx - ask) / point;

      double newSL = sl;
      double newTP = tp;

      // Fase 1: lucro pequeno -> trava minimo (nao deixa voltar ao prejuizo)
      if(favorPts >= InpSoftLockStart && favorPts < InpTrailStartPoints)
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

      // Fase 2: trailing + TP estendendo (degraus)
      if(favorPts >= InpTrailStartPoints)
      {
         int steps = (int)MathFloor((favorPts - InpTrailStartPoints) / InpTrailStepPoints) + 1;

         if(type == POSITION_TYPE_BUY)
         {
            double desiredSL = bid - InpLockPoints * point;
            if(desiredSL > sl + point)
               newSL = desiredSL;
            double desiredTP = openPx + (InpTakePoints + steps * InpTrailStepPoints) * point;
            if(desiredTP > tp + point)
               newTP = desiredTP;
         }
         else
         {
            double desiredSL = ask + InpLockPoints * point;
            if(sl == 0.0 || desiredSL < sl - point)
               newSL = desiredSL;
            double desiredTP = openPx - (InpTakePoints + steps * InpTrailStepPoints) * point;
            if(tp == 0.0 || desiredTP < tp - point)
               newTP = desiredTP;
         }
      }

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
         Print("TRAIL scalp ticket=", ticket, " favor=", (int)favorPts, "pts",
               " SL ", DoubleToString(sl, digits), "->", DoubleToString(newSL, digits),
               " TP ", DoubleToString(tp, digits), "->", DoubleToString(newTP, digits));
   }
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
   request.deviation = 25;
   request.magic = InpMagic;
   request.comment = "ScalpUSDJPY_v1.30";
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
