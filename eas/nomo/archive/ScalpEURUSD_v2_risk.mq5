//+------------------------------------------------------------------+
//| ScalpEURUSD_v2_risk.mq5                                          |
//| Demo/Real Nomo - scalp EURUSD com lote por risco %               |
//+------------------------------------------------------------------+
#property copyright "Vitor"
#property version   "2.10"
#property strict

input double InpRiskPercent   = 0.50;   // Risco por trade (% do saldo)
input double InpMaxLots         = 1.00;   // Teto de lote (seguranca)
input bool   InpUseFixedLots    = false;  // Usar lote fixo em vez de risco
input double InpFixedLots       = 0.01;   // Lote fixo (se UseFixedLots=true)
input int    InpStopPoints      = 150;    // Stop em pontos (15 pips)
input int    InpTakePoints      = 200;    // Alvo em pontos (20 pips)
input int    InpMaPeriod        = 20;     // Periodo da media
input int    InpMaxOpenPositions = 3;    // Max. posicoes abertas ao mesmo tempo
input int    InpMaxTradesDay    = 10;     // Max. trades no dia
input double InpMaxLossDay      = 15.0;   // Max. perda do dia (USD)
input int    InpMagic           = 260827; // Magic number

int maHandle = INVALID_HANDLE;
int tradesToday = 0;
double dayStartBalance = 0.0;
int dayStamp = 0;

int OnInit()
{
   maHandle = iMA(_Symbol, PERIOD_CURRENT, InpMaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE)
      return INIT_FAILED;

   ResetDayIfNeeded();
   Print("ScalpEURUSD_v2.10 iniciado | risco=", InpRiskPercent, "% | maxPos=",
         InpMaxOpenPositions, " | lote calc=", DoubleToString(CalculateLots(), 2));
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

   if(DayLossReached())
      return;

   if(CountOpenPositions() >= InpMaxOpenPositions)
      return;

   if(tradesToday >= InpMaxTradesDay)
      return;

   double ma[];
   if(CopyBuffer(maHandle, 0, 1, 3, ma) < 3)
      return;
   ArraySetAsSeries(ma, true);

   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);

   if(close2 <= ma[2] && close1 > ma[1])
   {
      OpenTrade(ORDER_TYPE_BUY);
      return;
   }

   if(close2 >= ma[2] && close1 < ma[1])
   {
      OpenTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Calcula lote com base no risco % e distancia do stop             |
//+------------------------------------------------------------------+
double CalculateLots()
{
   if(InpUseFixedLots)
      return NormalizeLots(InpFixedLots);

   if(InpRiskPercent <= 0.0 || InpStopPoints <= 0)
      return NormalizeLots(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double moneyRisk = balance * (InpRiskPercent / 100.0);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
      return NormalizeLots(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

   // Perda em dinheiro por 1 lote se o stop for atingido
   double stopDistance = InpStopPoints * point;
   double lossPerLot = (stopDistance / tickSize) * tickValue;

   if(lossPerLot <= 0.0)
      return NormalizeLots(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

   double lots = moneyRisk / lossPerLot;
   lots = MathMin(lots, InpMaxLots);

   return NormalizeLots(lots);
}

double NormalizeLots(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(stepLot <= 0.0)
      stepLot = 0.01;

   lots = MathFloor(lots / stepLot) * stepLot;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return lots;
}

bool DayLossReached()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double loss = dayStartBalance - equity;
   return (loss >= InpMaxLossDay);
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
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      count++;
   }
   return count;
}

bool OpenTrade(ENUM_ORDER_TYPE type)
{
   double lots = CalculateLots();
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("Lote calculado abaixo do minimo: ", lots);
      return false;
   }

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double sl = (type == ORDER_TYPE_BUY)
               ? price - InpStopPoints * point
               : price + InpStopPoints * point;

   double tp = (type == ORDER_TYPE_BUY)
               ? price + InpTakePoints * point
               : price - InpTakePoints * point;

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.volume    = lots;
   request.type      = type;
   request.price     = NormalizeDouble(price, digits);
   request.sl        = NormalizeDouble(sl, digits);
   request.tp        = NormalizeDouble(tp, digits);
   request.deviation = 20;
   request.magic     = InpMagic;
   request.comment   = "ScalpEURUSD_v2";
   request.type_filling = ResolveFilling();

   if(!OrderSend(request, result))
   {
      Print("Falha OrderSend: ", GetLastError(), " retcode=", result.retcode);
      return false;
   }

   if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED)
   {
      Print("Ordem rejeitada: ", result.retcode, " ", result.comment);
      return false;
   }

   tradesToday++;
   Print("Ordem OK: ", EnumToString(type),
         " lote=", DoubleToString(lots, 2),
         " risco~", DoubleToString(InpRiskPercent, 2), "%",
         " abertas=", CountOpenPositions(), "/", InpMaxOpenPositions,
         " tradesToday=", tradesToday);
   return true;
}

ENUM_ORDER_TYPE_FILLING ResolveFilling()
{
   int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}
