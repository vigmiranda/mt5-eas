//+------------------------------------------------------------------+
//| TrendMeme_Pct_v1.mq5                                             |
//| Trend/pump em % do preco (memecoin / crypto volatil)             |
//| Defaults calibrados para DOGEUSD Nomo (spread ~4.5-5%)           |
//| Validacao: 1 posicao, so BUY, trailing do topo + teto de lucro   |
//| v1.10: soft lock em % antes do trailing completo                 |
//+------------------------------------------------------------------+
#property copyright "Vitor"
#property version   "1.10"
#property strict

//--- risco
input double InpRiskPercent      = 0.25;  // Risco por trade (% saldo)
input double InpMaxLots          = 0.50;  // Teto de lote
input bool   InpUseFixedLots     = false;
input double InpFixedLots        = 0.01;

//--- entrada (impulso)
input int    InpBreakBars        = 10;    // Rompe max das ultimas N velas
input int    InpMaPeriod         = 20;
input bool   InpUseEmaFilter     = true;
input double InpMinBodyPct       = 1.5;   // Corpo minimo da vela (% do preco)
input double InpMinBreakPct      = 0.8;   // Rompimento minimo alem do HH (%)
input bool   InpOnlyBuy          = true;  // Memecoin: so compra (recomendado)

//--- stops / trailing em % do PRECO (DOGE: spread ~5%)
input double InpStopPct          = 18.0;  // SL inicial (% abaixo da entrada)
input double InpSoftLockArmPct   = 12.0;  // Trava lucro minimo antes do trail
input double InpSoftLockPct      = 5.0;   // SL = entrada + X% (compra)
input double InpTrailArmPct      = 25.0;  // Arma trailing apos +X% lucro
input double InpTrailLockPct     = 12.0;  // SL = mark * (1 - lock%) na compra
input double InpMaxProfitPct     = 100.0; // Teto: fecha em +X% lucro
input double InpPartialPct       = 0.0;   // 0=off; ex. 40 = realiza parcial em +40%
input double InpPartialCloseFrac = 0.50;  // Fracao fechada no parcial (0.5 = 50%)

//--- filtros operacionais
input double InpMaxSpreadPct     = 6.0;   // DOGE Nomo ~4.85% -> precisa > isso
input int    InpMaxOpenPositions = 1;     // Validacao: 1 posicao
input int    InpMaxTradesDay     = 4;
input double InpMaxLossDayPct    = 2.0;
input int    InpMagic            = 310901;

input bool   InpCloseBeforeSwap  = true;  // Flat perto do rollover crypto
input int    InpFlatHour         = 21;
input int    InpFlatMinute       = 50;
input bool   InpVerboseLog       = true;

int maHandle = INVALID_HANDLE;
int tradesToday = 0;
double dayStartBalance = 0.0;
int dayStamp = 0;
datetime lastBarChecked = 0;
bool partialDone = false;

int OnInit()
{
   maHandle = iMA(_Symbol, PERIOD_CURRENT, InpMaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE)
      return INIT_FAILED;

   ResetDayIfNeeded();

   Print("TrendMeme_Pct_v1.10 | ", _Symbol, " ", EnumToString(_Period));
   Print("SL=", InpStopPct, "% | softLock=+", InpSoftLockArmPct,
         "% (+", InpSoftLockPct, "%) | armTrail=+", InpTrailArmPct,
         "% | lock=", InpTrailLockPct, "% | teto=+", InpMaxProfitPct, "%");
   Print("spreadAtual=", DoubleToString(CurrentSpreadPct(), 3),
         "% | max=", InpMaxSpreadPct, "% | onlyBuy=", InpOnlyBuy);
   Print("digits=", SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
         " point=", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_POINT), 8));

   if(CurrentSpreadPct() > InpMaxSpreadPct)
      Print("AVISO: spread atual acima do max. EA nao entra ate baixar ou voce subir InpMaxSpreadPct.");

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

   if(InpCloseBeforeSwap && IsFlatWindow())
   {
      CloseOurPositions("flat_window");
      return;
   }

   if(CountOpenPositions() > 0)
      ManageOpenPosition();

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

   double spreadPct = CurrentSpreadPct();
   if(spreadPct > InpMaxSpreadPct)
   {
      if(InpVerboseLog)
         Print("Skip: spread ", DoubleToString(spreadPct, 3), "% > ", InpMaxSpreadPct, "%");
      return;
   }

   if(Bars(_Symbol, PERIOD_CURRENT) < InpBreakBars + 5)
      return;

   double ma[];
   if(CopyBuffer(maHandle, 0, 1, 3, ma) < 3)
      return;
   ArraySetAsSeries(ma, true);

   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open1  = iOpen(_Symbol, PERIOD_CURRENT, 1);
   if(close1 <= 0.0)
      return;

   double bodyPct = MathAbs(close1 - open1) / close1 * 100.0;
   if(bodyPct < InpMinBodyPct)
   {
      if(InpVerboseLog)
         Print("Skip: corpo fraco ", DoubleToString(bodyPct, 2), "% < ", InpMinBodyPct, "%");
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
      double breakPct = (close1 - hh) / close1 * 100.0;
      if(breakPct < InpMinBreakPct)
      {
         if(InpVerboseLog)
            Print("Skip BUY: rompimento fraco ", DoubleToString(breakPct, 3), "%");
      }
      else if(InpUseEmaFilter && close1 < ma[1])
      {
         if(InpVerboseLog)
            Print("Skip BUY: abaixo EMA", InpMaPeriod);
      }
      else
      {
         Print("SINAL BUY | body=", DoubleToString(bodyPct, 2),
               "% break=", DoubleToString(breakPct, 2),
               "% spread=", DoubleToString(spreadPct, 3), "%");
         if(OpenTrade(ORDER_TYPE_BUY))
            partialDone = false;
         return;
      }
   }

   if(!InpOnlyBuy && bear && close1 < ll)
   {
      double breakPct = (ll - close1) / close1 * 100.0;
      if(breakPct < InpMinBreakPct)
      {
         if(InpVerboseLog)
            Print("Skip SELL: rompimento fraco ", DoubleToString(breakPct, 3), "%");
      }
      else if(InpUseEmaFilter && close1 > ma[1])
      {
         if(InpVerboseLog)
            Print("Skip SELL: acima EMA", InpMaPeriod);
      }
      else
      {
         Print("SINAL SELL | body=", DoubleToString(bodyPct, 2),
               "% break=", DoubleToString(breakPct, 2),
               "% spread=", DoubleToString(spreadPct, 3), "%");
         if(OpenTrade(ORDER_TYPE_SELL))
            partialDone = false;
         return;
      }
   }

   if(InpVerboseLog)
      Print("Skip: sem impulso | c=", close1, " hh=", hh, " ll=", ll);
}

void ManageOpenPosition()
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
      double vol    = PositionGetDouble(POSITION_VOLUME);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      double mark = (type == POSITION_TYPE_BUY) ? bid : ask;
      if(openPx <= 0.0 || mark <= 0.0)
         continue;

      double profitPct = (type == POSITION_TYPE_BUY)
                         ? (mark - openPx) / openPx * 100.0
                         : (openPx - mark) / openPx * 100.0;

      if(profitPct >= InpMaxProfitPct)
      {
         Print("TETO +", DoubleToString(profitPct, 2), "% -> fecha ticket=", ticket);
         ClosePositionTicket(ticket, "max_profit");
         continue;
      }

      if(InpPartialPct > 0.0 && !partialDone && profitPct >= InpPartialPct)
      {
         double closeVol = NormalizeLots(vol * InpPartialCloseFrac);
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(closeVol >= minLot && vol - closeVol >= minLot - 1e-8)
         {
            if(ClosePartialTicket(ticket, closeVol, "partial"))
            {
               partialDone = true;
               Print("PARCIAL ", DoubleToString(closeVol, 2), " @ +",
                     DoubleToString(profitPct, 2), "%");
            }
         }
      }

      double newSL = sl;

      if(profitPct >= InpSoftLockArmPct && profitPct < InpTrailArmPct)
      {
         if(type == POSITION_TYPE_BUY)
         {
            double softSL = openPx * (1.0 + InpSoftLockPct / 100.0);
            if(softSL > sl + point)
               newSL = softSL;
         }
         else
         {
            double softSL = openPx * (1.0 - InpSoftLockPct / 100.0);
            if(sl == 0.0 || softSL < sl - point)
               newSL = softSL;
         }
      }

      if(profitPct >= InpTrailArmPct)
      {
         if(type == POSITION_TYPE_BUY)
         {
            double desiredSL = mark * (1.0 - InpTrailLockPct / 100.0);
            if(desiredSL > openPx)
            {
               if(desiredSL > newSL + point)
                  newSL = desiredSL;
            }
         }
         else
         {
            double desiredSL = mark * (1.0 + InpTrailLockPct / 100.0);
            if(desiredSL < openPx)
            {
               if(newSL == 0.0 || desiredSL < newSL - point)
                  newSL = desiredSL;
            }
         }
      }

      if(profitPct < InpSoftLockArmPct)
         continue;

      newSL = NormalizeDouble(newSL, digits);
      if(MathAbs(newSL - sl) < point)
         continue;

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);
      request.action   = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol   = _Symbol;
      request.sl       = newSL;
      request.tp       = tp;
      request.magic    = InpMagic;

      if(!OrderSend(request, result))
         Print("Falha trailing ticket=", ticket, " err=", GetLastError());
      else if(profitPct >= InpTrailArmPct)
         Print("TRAIL +", DoubleToString(profitPct, 2), "% SL ",
               DoubleToString(sl, digits), "->", DoubleToString(newSL, digits));
      else
         Print("SOFT +", DoubleToString(profitPct, 2), "% SL ",
               DoubleToString(sl, digits), "->", DoubleToString(newSL, digits));
   }
}

bool IsFlatWindow()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int mins = now.hour * 60 + now.min;
   return (mins >= InpFlatHour * 60 + InpFlatMinute && mins <= 22 * 60 + 10);
}

double CurrentSpreadPct()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double mid = (bid + ask) * 0.5;
   if(mid <= 0.0) return 999.0;
   return (ask - bid) / mid * 100.0;
}

double CalculateLots()
{
   if(InpUseFixedLots)
      return NormalizeLots(InpFixedLots);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double moneyRisk = balance * (InpRiskPercent / 100.0);
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(price <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0 || InpStopPct <= 0.0)
      return NormalizeLots(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

   double slDist = price * (InpStopPct / 100.0);
   double lossPerLot = (slDist / tickSize) * tickValue;
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
      ClosePositionTicket(ticket, reason);
   }
}

bool ClosePositionTicket(const ulong ticket, const string reason)
{
   if(!PositionSelectByTicket(ticket))
      return false;

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
   request.deviation = 80;
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
   {
      Print("Falha close: ", GetLastError(), " ", result.retcode);
      return false;
   }
   return true;
}

bool ClosePartialTicket(const ulong ticket, const double volume, const string reason)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   long type = PositionGetInteger(POSITION_TYPE);

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = _Symbol;
   request.volume = volume;
   request.deviation = 80;
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
   {
      Print("Falha parcial: ", GetLastError(), " ", result.retcode);
      return false;
   }
   return (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED);
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
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double sl = (type == ORDER_TYPE_BUY)
               ? price * (1.0 - InpStopPct / 100.0)
               : price * (1.0 + InpStopPct / 100.0);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = type;
   request.price = NormalizeDouble(price, digits);
   request.sl = NormalizeDouble(sl, digits);
   request.tp = 0.0;
   request.deviation = 80;
   request.magic = InpMagic;
   request.comment = "TrendMeme_Pct_v1.10";
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
         " @ ", DoubleToString(price, digits),
         " SL=", DoubleToString(request.sl, digits),
         " (", InpStopPct, "%)",
         " spread=", DoubleToString(CurrentSpreadPct(), 3), "%");
   return true;
}

ENUM_ORDER_TYPE_FILLING ResolveFilling()
{
   int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}
