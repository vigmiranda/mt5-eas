//+------------------------------------------------------------------+
//| NMAI_BuyDip_v1.mq5                                               |
//| Nomo AI Index - so BUY, 1 posicao, sem TP                        |
//| Soft lock progressivo sobe com o lucro; ao fechar, espera dip    |
//| Spread tipico ~6 pts | comissao ~US$4.99 | lote fixo = 1         |
//| Grafico recomendado: NMAI H1                                     |
//+------------------------------------------------------------------+
#property copyright "Vitor"
#property version   "1.00"
#property strict

//--- lote (NMAI: min=max=step=1)
input bool   InpUseFixedLots     = true;
input double InpFixedLots        = 1.0;   // NMAI: obrigatorio 1.0

//--- entrada (buy the dip / mean reversion)
input int    InpLookbackBars     = 12;    // Janela para achar o fundo recente
input int    InpMaPeriod         = 20;    // EMA (compra preferencialmente abaixo)
input bool   InpRequireBelowEma  = true;  // Dip: close abaixo da EMA
input int    InpRsiPeriod        = 14;
input double InpRsiBuyLevel      = 38.0;  // RSI abaixo = oversold (entrada)
input double InpMinLowerWickATR  = 0.35;  // Pavio inferior minimo (fator * ATR)
input int    InpATRPeriod        = 14;

//--- stops / soft lock progressivo (pontos; point=0.01 => 100 pts ~ US$1)
// Comissao ~US$4.99 => arma soft lock so apos cobrir custo + folga
input int    InpStopPoints       = 2500;  // SL inicial ~US$25 (abaixo do dip)
input int    InpSoftLockStart    = 1000;  // Arma apos ~US$10 de lucro
input int    InpSoftLockPts      = 500;   // Lucro minimo travado (~US$5)
input int    InpTrailLockPts     = 800;   // Soft lock sobe: SL = Bid - X pts

//--- filtros
input int    InpMaxSpreadPoints  = 20;    // Normal ~6; bloqueia se estourar
input int    InpMaxOpenPositions = 1;     // Sempre no maximo 1 na carteira
input int    InpMaxTradesDay     = 2;     // Comissao alta: poucas entradas
input double InpMaxLossDayPct    = 3.0;
input int    InpMagic            = 310904;

input bool   InpCloseBeforeSwap  = false; // Hold multi-dia: false recomendado
input int    InpFlatHour         = 20;
input int    InpFlatMinute       = 50;
input bool   InpVerboseLog       = true;

int maHandle  = INVALID_HANDLE;
int atrHandle = INVALID_HANDLE;
int rsiHandle = INVALID_HANDLE;
int tradesToday = 0;
double dayStartBalance = 0.0;
int dayStamp = 0;
datetime lastBarChecked = 0;

int OnInit()
{
   maHandle  = iMA(_Symbol, PERIOD_CURRENT, InpMaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE)
      return INIT_FAILED;

   ResetDayIfNeeded();

   int spr = CurrentSpreadPoints();
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   Print("NMAI_BuyDip_v1.00 | ", _Symbol, " ", EnumToString(_Period));
   Print("ONLY BUY | maxPos=1 | lote=", InpFixedLots, " | sem TP | softLock progressivo");
   Print("spread=", spr, " pts (~US$", DoubleToString(spr * point, 2),
         ") | max=", InpMaxSpreadPoints);
   Print("SL ini=", InpStopPoints, " | armSoft=", InpSoftLockStart,
         " | lockMin=", InpSoftLockPts, " | trailLock=", InpTrailLockPts);
   Print("digits=", SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
         " point=", DoubleToString(point, 8));

   if(InpSoftLockStart < 600)
      Print("AVISO: SoftLockStart baixo vs comissao ~US$4.99. Prefira >= 1000 pts.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(maHandle != INVALID_HANDLE)  IndicatorRelease(maHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
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

   // Sempre gerencia a posicao unica (soft lock sobe)
   if(CountOpenPositions() > 0)
   {
      ManageSoftLock();
      return; // carteira cheia: nao procura nova entrada
   }

   // Sem posicao: espera boa oportunidade de dip
   if(DayLossReached())
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
         Print("Skip: spread ", spread, " > ", InpMaxSpreadPoints);
      return;
   }

   if(Bars(_Symbol, PERIOD_CURRENT) < MathMax(InpLookbackBars, InpATRPeriod) + 5)
      return;

   double ma[], atr[], rsi[];
   if(CopyBuffer(maHandle, 0, 1, 3, ma) < 3) return;
   if(CopyBuffer(atrHandle, 0, 1, 3, atr) < 3) return;
   if(CopyBuffer(rsiHandle, 0, 1, 3, rsi) < 3) return;
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(rsi, true);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open1  = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double low1   = iLow(_Symbol, PERIOD_CURRENT, 1);
   double high1  = iHigh(_Symbol, PERIOD_CURRENT, 1);
   if(close1 <= 0.0) return;

   // Precisa ser vela de recuperacao (bullish)
   if(close1 <= open1)
   {
      if(InpVerboseLog)
         Print("Skip: sem reclaim bullish | c=", close1);
      return;
   }

   // Pavio inferior (comprou a baixa intrabar)
   double lowerWick = MathMin(open1, close1) - low1;
   double minWick = atr[1] * InpMinLowerWickATR;
   if(lowerWick < minWick)
   {
      if(InpVerboseLog)
         Print("Skip: pavio fraco ", DoubleToString(lowerWick / point, 1),
               " < ", DoubleToString(minWick / point, 1), " pts");
      return;
   }

   // Fundo recente (barras 2..Lookback)
   double ll = iLow(_Symbol, PERIOD_CURRENT, 2);
   for(int i = 3; i <= InpLookbackBars; i++)
      ll = MathMin(ll, iLow(_Symbol, PERIOD_CURRENT, i));

   // Dip: tocou/quase tocou o fundo e fechou acima
   bool touchedDip = (low1 <= ll + atr[1] * 0.15);
   if(!touchedDip)
   {
      if(InpVerboseLog)
         Print("Skip: nao tocou fundo | low=", low1, " ll=", ll);
      return;
   }

   if(InpRequireBelowEma && close1 > ma[1])
   {
      if(InpVerboseLog)
         Print("Skip: close acima EMA", InpMaPeriod, " (nao e dip)");
      return;
   }

   if(rsi[1] > InpRsiBuyLevel)
   {
      if(InpVerboseLog)
         Print("Skip: RSI ", DoubleToString(rsi[1], 1), " > ", InpRsiBuyLevel);
      return;
   }

   Print("SINAL BUY DIP | RSI=", DoubleToString(rsi[1], 1),
         " | wick=", DoubleToString(lowerWick / point, 1),
         " pts | spread=", spread, " | close=", close1);
   OpenBuy();
}

// Soft lock progressivo: sem TP. SL so sobe.
void ManageSoftLock()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;

      double openPx = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      double favorMove = (bid - openPx) / point;
      if(favorMove < InpSoftLockStart)
         continue;

      // 1) lucro minimo travado acima da entrada
      double minLockSL = openPx + InpSoftLockPts * point;
      // 2) soft lock sobe atras do preco
      double trailSL   = bid - InpTrailLockPts * point;

      double newSL = MathMax(minLockSL, trailSL);
      if(sl > 0.0)
         newSL = MathMax(newSL, sl); // nunca desce

      newSL = NormalizeDouble(newSL, digits);
      if(newSL <= sl + point * 0.5)
         continue;
      if(newSL >= bid - point) // SL nao pode ficar no/acima do Bid
         continue;

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);
      request.action   = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol   = _Symbol;
      request.sl       = newSL;
      request.tp       = 0.0; // sem mira
      request.magic    = InpMagic;

      if(!OrderSend(request, result))
         Print("Falha softLock ticket=", ticket, " err=", GetLastError());
      else
         Print("SOFT+ favor=", (int)favorMove, "pts SL ",
               DoubleToString(sl, digits), "->", DoubleToString(newSL, digits),
               " (~US$", DoubleToString((newSL - openPx), 2), " travados)");
   }
}

bool IsFlatWindow()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int mins = now.hour * 60 + now.min;
   return (mins >= InpFlatHour * 60 + InpFlatMinute && mins <= 21 * 60 + 10);
}

int CurrentSpreadPoints()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) return 999999;
   return (int)MathRound((SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / point);
}

double NormalizeLots(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0) stepLot = 1.0;
   lots = MathFloor(lots / stepLot + 1e-12) * stepLot;
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
      Print("Novo dia. Balance base: ", dayStartBalance,
            " | posicoes=", CountOpenPositions());
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

      double volume = PositionGetDouble(POSITION_VOLUME);
      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);
      request.action = TRADE_ACTION_DEAL;
      request.position = ticket;
      request.symbol = _Symbol;
      request.volume = volume;
      request.type = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      request.deviation = 50;
      request.magic = InpMagic;
      request.comment = reason;
      request.type_filling = ResolveFilling();
      if(!OrderSend(request, result))
         Print("Falha flat: ", GetLastError());
   }
}

bool OpenBuy()
{
   if(CountOpenPositions() >= InpMaxOpenPositions)
      return false;

   double lots = NormalizeLots(InpFixedLots);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      return false;

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = ORDER_TYPE_BUY;
   request.price = NormalizeDouble(price, digits);
   request.sl = NormalizeDouble(price - InpStopPoints * point, digits);
   request.tp = 0.0; // sem mira — so soft lock progressivo
   request.deviation = 50;
   request.magic = InpMagic;
   request.comment = "NMAI_BuyDip_v1";
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
   Print("ENTROU BUY lote=", DoubleToString(lots, 2),
         " @ ", DoubleToString(price, digits),
         " SL=", DoubleToString(request.sl, digits),
         " TP=0 (soft lock) | spread=", CurrentSpreadPoints(),
         " | tradesHoje=", tradesToday);
   return true;
}

ENUM_ORDER_TYPE_FILLING ResolveFilling()
{
   int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}
