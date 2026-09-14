//+------------------------------------------------------------------+
//| ScalpXRPUSD_v1.mq5                                               |
//| Nomo - scalp XRPUSD 24/7 com risco %, filtro de spread           |
//| e sem carregar overnight (swap -29%)                             |
//+------------------------------------------------------------------+
#property copyright "Vitor"
#property version   "1.20"
#property strict

input double InpRiskPercent     = 0.50;   // Risco por trade (% do saldo)
input double InpMaxLots         = 1.00;   // Teto de lote
input bool   InpUseFixedLots    = false;  // Usar lote fixo
input double InpFixedLots       = 0.01;   // Lote fixo
input int    InpStopPoints      = 250;    // Stop em pontos (ajustar na demo)
input int    InpTakePoints      = 400;    // Alvo em pontos (maior que o spread)
input int    InpMaPeriod        = 20;     // Periodo da EMA
input int    InpMaxSpreadPoints = 120;    // Nao entra se spread > isso
input int    InpMaxOpenPositions = 3;    // Max. posicoes abertas ao mesmo tempo
input int    InpMaxTradesDay    = 20;     // Max. trades no dia
input double InpMaxLossDayPct   = 2.0;    // Max. perda do dia (% do saldo)
input int    InpMagic           = 300830; // Magic (diferente do EURUSD)
input bool   InpCloseBeforeSwap = true;   // Fechar antes da janela de swap/manutencao
input int    InpFlatHour        = 21;     // Hora (servidor) para zerar posicao
input int    InpFlatMinute      = 50;     // Minuto para zerar posicao

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
   Print("ScalpXRPUSD_v1.10 iniciado em ", _Symbol, " ", EnumToString(_Period),
         " | maxPos=", InpMaxOpenPositions,
         " | risco=", InpRiskPercent, "% | lote~", DoubleToString(CalculateLots(), 2));
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

   // Evita carregar pelo swap agressivo / pausa da corretora
   if(InpCloseBeforeSwap && IsFlatWindow())
   {
      CloseOurPositions("flat_window");
      return;
   }

   if(DayLossReached())
      return;

   if(CountOpenPositions() >= InpMaxOpenPositions)
      return;

   if(tradesToday >= InpMaxTradesDay)
      return;

   if(CurrentSpreadPoints() > InpMaxSpreadPoints)
      return;

   double ma[];
   if(CopyBuffer(maHandle, 0, 1, 3, ma) < 3)
      return;
   ArraySetAsSeries(ma, true);

   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);

   // Compra: cruza EMA para cima
   if(close2 <= ma[2] && close1 > ma[1])
   {
      OpenTrade(ORDER_TYPE_BUY);
      return;
   }

   // Venda: cruza EMA para baixo
   if(close2 >= ma[2] && close1 < ma[1])
   {
      OpenTrade(ORDER_TYPE_SELL);
   }
}

bool IsFlatWindow()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int mins = now.hour * 60 + now.min;
   int flatFrom = InpFlatHour * 60 + InpFlatMinute; // 21:50
   int flatTo   = 22 * 60 + 10;                     // 22:10
   return (mins >= flatFrom && mins <= flatTo);
}

int CurrentSpreadPoints()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 999999;
   return (int)MathRound((ask - bid) / point);
}

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
   double maxLossMoney = dayStartBalance * (InpMaxLossDayPct / 100.0);
   double loss = dayStartBalance - equity;
   return (loss >= maxLossMoney);
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

void CloseOurPositions(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

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
         Print("Falha ao flat: ", GetLastError(), " ", result.retcode);
      else
         Print("Posicao flat por ", reason, " ticket=", ticket);
   }
}

bool OpenTrade(ENUM_ORDER_TYPE type)
{
   double lots = CalculateLots();
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("Lote abaixo do minimo: ", lots);
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
   request.deviation = 30;
   request.magic     = InpMagic;
   request.comment   = "ScalpXRPUSD_v1";
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
         " spread=", CurrentSpreadPoints(),
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
