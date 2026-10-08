//+------------------------------------------------------------------+
//| Nomo_Futures_Grid_Bot.mq5                                        |
//| EXPERIMENTAL — conflita com REGRAS (sem grid / 1 posição)        |
//| Uso: teste Nomo BTCUSD conta ~US$300 | lote 0.01                 |
//| v1.01: log margem 0.01 + só arma níveis que a free margin cabe  |
//+------------------------------------------------------------------+
#property copyright "Vitor / mt5-eas (experimental)"
#property version   "1.01"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

input group "=== EXPERIMENTAL / risco conta pequena ==="
input double   InpLotSize       = 0.01;   // Lote por nível (mínimo Nomo)
input int      InpGridLevels    = 3;      // Níveis (conta ~US$300: 2–3; máx 8)
input double   InpRangePct      = 2.0;    // Faixa total ±% em torno do preço
input bool     InpAutoRange     = true;   // true = calcula upper/lower pelo preço atual
input double   InpUpperPrice    = 0.0;    // Só se AutoRange=false
input double   InpLowerPrice    = 0.0;    // Só se AutoRange=false

input group "=== Nomo / BTC ==="
input ulong    InpMagic         = 310940; // Único (TrendBTC=310903)
input int      InpMaxSlippage   = 80;     // BTC: slippage maior
input bool     InpCloseOnBreak  = true;   // Fora da faixa: fecha posições + cancela pendentes
input bool     InpRefillGrid    = true;   // Recria nível faltante após fill
input string   InpCommentBuy    = "GridBTC_Buy";
input string   InpCommentSell   = "GridBTC_Sell";
input bool     InpVerboseLog    = true;

double g_upper = 0.0;
double g_lower = 0.0;
double g_step  = 0.0;
int    g_levels = 0;
datetime g_lastMaintain = 0;
double g_marginBuy  = 0.0;
double g_marginSell = 0.0;
int    g_maxAfford  = 0;
bool   g_marginSkipLogged = false;

//+------------------------------------------------------------------+
double NormalizeLots(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   if(minLot <= 0.0) minLot = 0.01;
   lots = MathFloor(lots / step + 1e-12) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
double SnapPrice(const double price)
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0) ts = _Point;
   if(ts <= 0.0) return price;
   return NormalizeDouble(MathRound(price / ts) * ts, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
bool IsBtcLike()
{
   string s = _Symbol;
   StringToUpper(s);
   return (StringFind(s, "BTC") >= 0 || StringFind(s, "BITCOIN") >= 0);
}

//+------------------------------------------------------------------+
// Margem usa BUY/SELL (Limit não é confiável em OrderCalcMargin)
double CalcMarginRequired(const bool isBuy, const double lots, const double price)
{
   double margin = 0.0;
   ENUM_ORDER_TYPE typ = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(typ, _Symbol, lots, price, margin))
      return 0.0;
   return margin;
}

//+------------------------------------------------------------------+
bool MarginOk(const bool isBuy, const double lots, const double price, double &outMargin)
{
   outMargin = CalcMarginRequired(isBuy, lots, price);
   if(outMargin <= 0.0)
      return true; // broker não calculou — deixa o servidor decidir
   double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   return (free > outMargin * 1.3);
}

//+------------------------------------------------------------------+
void RefreshMarginDiag()
{
   double lots = NormalizeLots(InpLotSize);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0) bid = ask;
   if(ask <= 0.0) ask = bid;
   if(bid <= 0.0) return;

   g_marginBuy  = CalcMarginRequired(true,  lots, ask);
   g_marginSell = CalcMarginRequired(false, lots, bid);

   double need = MathMax(g_marginBuy, g_marginSell);
   double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(need <= 0.0)
      g_maxAfford = 0;
   else
      g_maxAfford = (int)MathFloor(free / (need * 1.3));
}

//+------------------------------------------------------------------+
int CountOurPendings()
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      n++;
   }
   return n;
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
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
bool HasPendingNear(const double price, const int typeBuyLimitOrSellLimit)
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0) ts = _Point;
   double tol = MathMax(ts * 2.0, g_step * 0.15);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      long typ = OrderGetInteger(ORDER_TYPE);
      if(typ != typeBuyLimitOrSellLimit) continue;
      double op = OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(op - price) <= tol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool HasPositionNear(const double price, const long posType)
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0) ts = _Point;
   double tol = MathMax(ts * 5.0, g_step * 0.25);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_TYPE) != posType) continue;
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(op - price) <= tol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void CancelOurPendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(!trade.OrderDelete(ticket) && InpVerboseLog)
         PrintFormat("[GridBTC] delete pendente falhou %I64u ret=%u", ticket, trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
void CloseOurPositions(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!trade.PositionClose(ticket) && InpVerboseLog)
         PrintFormat("[GridBTC] close %I64u falhou ret=%u (%s)", ticket, trade.ResultRetcode(), reason);
   }
}

//+------------------------------------------------------------------+
bool ResolveRange()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0) return false;

   if(InpAutoRange)
   {
      double half = MathAbs(InpRangePct) / 100.0;
      if(half <= 0.0) half = 0.02;
      g_lower = SnapPrice(bid * (1.0 - half));
      g_upper = SnapPrice(bid * (1.0 + half));
   }
   else
   {
      g_lower = SnapPrice(InpLowerPrice);
      g_upper = SnapPrice(InpUpperPrice);
   }

   if(g_upper <= g_lower) return false;

   g_levels = InpGridLevels;
   if(g_levels < 2) g_levels = 2;
   if(g_levels > 8) g_levels = 8;

   g_step = (g_upper - g_lower) / g_levels;
   if(g_step <= 0.0) return false;
   return true;
}

//+------------------------------------------------------------------+
double TpForBuy(const double entry)
{
   return SnapPrice(entry + g_step);
}

//+------------------------------------------------------------------+
double TpForSell(const double entry)
{
   return SnapPrice(entry - g_step);
}

//+------------------------------------------------------------------+
// true = enviou; false = não enviou (já existe / margem / falha)
bool PlaceBuyLimit(const double price)
{
   double lots = NormalizeLots(InpLotSize);
   double px = SnapPrice(price);
   if(px <= 0.0 || lots <= 0.0) return false;
   if(HasPendingNear(px, ORDER_TYPE_BUY_LIMIT)) return false;
   if(HasPositionNear(px, POSITION_TYPE_BUY)) return false;

   double need = 0.0;
   if(!MarginOk(true, lots, px, need))
   {
      if(InpVerboseLog && !g_marginSkipLogged)
      {
         g_marginSkipLogged = true;
         PrintFormat("[GridBTC] margem insuficiente — precisa ~%.2f free=%.2f (lote %.2f). Parando de armar níveis.",
                     need * 1.3, AccountInfoDouble(ACCOUNT_MARGIN_FREE), lots);
      }
      return false;
   }

   double tp = TpForBuy(px);
   if(tp <= px) tp = 0.0;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpMaxSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   if(!trade.BuyLimit(lots, px, _Symbol, 0.0, tp, ORDER_TIME_GTC, 0, InpCommentBuy))
   {
      PrintFormat("[GridBTC] BuyLimit falhou @ %.2f ret=%u %s", px, trade.ResultRetcode(), trade.ResultComment());
      return false;
   }
   if(InpVerboseLog)
      PrintFormat("[GridBTC] BuyLimit %.2f lot=%.2f tp=%.2f margem~%.2f", px, lots, tp, need);
   return true;
}

//+------------------------------------------------------------------+
bool PlaceSellLimit(const double price)
{
   double lots = NormalizeLots(InpLotSize);
   double px = SnapPrice(price);
   if(px <= 0.0 || lots <= 0.0) return false;
   if(HasPendingNear(px, ORDER_TYPE_SELL_LIMIT)) return false;
   if(HasPositionNear(px, POSITION_TYPE_SELL)) return false;

   double need = 0.0;
   if(!MarginOk(false, lots, px, need))
   {
      if(InpVerboseLog && !g_marginSkipLogged)
      {
         g_marginSkipLogged = true;
         PrintFormat("[GridBTC] margem insuficiente — precisa ~%.2f free=%.2f (lote %.2f). Parando de armar níveis.",
                     need * 1.3, AccountInfoDouble(ACCOUNT_MARGIN_FREE), lots);
      }
      return false;
   }

   double tp = TpForSell(px);
   if(tp >= px || tp <= 0.0) tp = 0.0;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpMaxSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   if(!trade.SellLimit(lots, px, _Symbol, 0.0, tp, ORDER_TIME_GTC, 0, InpCommentSell))
   {
      PrintFormat("[GridBTC] SellLimit falhou @ %.2f ret=%u %s", px, trade.ResultRetcode(), trade.ResultComment());
      return false;
   }
   if(InpVerboseLog)
      PrintFormat("[GridBTC] SellLimit %.2f lot=%.2f tp=%.2f margem~%.2f", px, lots, tp, need);
   return true;
}

//+------------------------------------------------------------------+
// Ordena níveis pelo mais próximo do preço e só arma o que a margem cabe
void SetupOrMaintainGrid()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0) return;

   RefreshMarginDiag();
   if(g_maxAfford <= 0 && g_marginBuy > 0.0)
   {
      if(InpVerboseLog && !g_marginSkipLogged)
      {
         g_marginSkipLogged = true;
         PrintFormat("[GridBTC] conta NÃO comporta lote %.2f | margemBuy=%.2f margemSell=%.2f free=%.2f",
                     NormalizeLots(InpLotSize), g_marginBuy, g_marginSell,
                     AccountInfoDouble(ACCOUNT_MARGIN_FREE));
      }
      return;
   }

   // candidatos: distância ao bid, preço, isBuy
   double prices[];
   double dists[];
   bool   isBuy[];
   int nCand = 0;
   ArrayResize(prices, g_levels + 1);
   ArrayResize(dists, g_levels + 1);
   ArrayResize(isBuy, g_levels + 1);

   for(int i = 0; i <= g_levels; i++)
   {
      double level = SnapPrice(g_lower + i * g_step);
      if(level <= g_lower - g_step * 0.01) continue;
      if(level >= g_upper + g_step * 0.01) continue;

      if(level < bid - g_step * 0.05)
      {
         prices[nCand] = level;
         dists[nCand]  = bid - level;
         isBuy[nCand]  = true;
         nCand++;
      }
      else if(level > bid + g_step * 0.05)
      {
         prices[nCand] = level;
         dists[nCand]  = level - bid;
         isBuy[nCand]  = false;
         nCand++;
      }
   }

   // bubble sort por distância (mais perto primeiro)
   for(int a = 0; a < nCand - 1; a++)
   {
      for(int b = a + 1; b < nCand; b++)
      {
         if(dists[b] < dists[a])
         {
            double td = dists[a]; dists[a] = dists[b]; dists[b] = td;
            double tp = prices[a]; prices[a] = prices[b]; prices[b] = tp;
            bool tb = isBuy[a]; isBuy[a] = isBuy[b]; isBuy[b] = tb;
         }
      }
   }

   int placedOrExisting = CountOurPendings() + CountOurPositions();
   int budget = g_maxAfford;
   if(budget > g_levels + 1) budget = g_levels + 1;

   for(int k = 0; k < nCand; k++)
   {
      if(placedOrExisting >= budget)
         break;

      bool ok = false;
      if(isBuy[k])
         ok = PlaceBuyLimit(prices[k]);
      else
         ok = PlaceSellLimit(prices[k]);

      if(ok)
         placedOrExisting++;
      else if(g_marginSkipLogged)
         break; // sem margem — não tenta níveis mais longe
   }
}

//+------------------------------------------------------------------+
void UpdateComment(const string extra = "")
{
   double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   string txt = StringFormat(
      "GridBTC EXP v1.01 | %s\nfaixa %.0f–%.0f | step %.1f | níveis %d | lot %.2f\n"
      "margem 0.01 buy~%.2f sell~%.2f | free=%.2f | max≈%d\n"
      "pend=%d pos=%d | magic %I64d\n%s",
      _Symbol, g_lower, g_upper, g_step, g_levels, NormalizeLots(InpLotSize),
      g_marginBuy, g_marginSell, free, g_maxAfford,
      CountOurPendings(), CountOurPositions(), InpMagic, extra
   );
   Comment(txt);
}

//+------------------------------------------------------------------+
int OnInit()
{
   Print("[GridBTC] AVISO: EA EXPERIMENTAL com GRID — conflita com REGRAS do projeto (sem grid / 1 pos). Use só teste/demo.");

   if(!IsBtcLike())
      Print("[GridBTC] aviso: símbolo não parece BTC: ", _Symbol);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpMaxSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(!ResolveRange())
   {
      Print("[GridBTC] faixa inválida (AutoRange ou Upper/Lower).");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(NormalizeLots(InpLotSize) > NormalizeLots(0.01) + 1e-8)
      Print("[GridBTC] AVISO: lote > 0.01 em conta ~US$300 aumenta risco de stop-out.");

   RefreshMarginDiag();
   double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   PrintFormat("[GridBTC] init %s | upper=%.2f lower=%.2f step=%.2f levels=%d lot=%.2f magic=%I64d",
               _Symbol, g_upper, g_lower, g_step, g_levels, NormalizeLots(InpLotSize), InpMagic);
   PrintFormat("[GridBTC] MARGEM 0.01 | buy≈%.2f sell≈%.2f | free=%.2f | maxPendentes≈%d (fator 1.3x)",
               g_marginBuy, g_marginSell, free, g_maxAfford);

   if(g_maxAfford <= 0 && g_marginBuy > 0.0)
      Print("[GridBTC] Conta pequena demais para 0.01 BTC neste broker — grid não vai armar até haver margem livre.");

   g_marginSkipLogged = false;
   SetupOrMaintainGrid();
   UpdateComment("grid montado");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   CancelOurPendings();
   PrintFormat("[GridBTC] deinit reason=%d | pendentes canceladas", reason);
}

//+------------------------------------------------------------------+
void OnTick()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0) return;

   if(InpCloseOnBreak && (bid > g_upper || bid < g_lower))
   {
      UpdateComment("FORA DA FAIXA → flat");
      static datetime lastBreakLog = 0;
      datetime now = TimeTradeServer();
      if(now != lastBreakLog)
      {
         lastBreakLog = now;
         PrintFormat("[GridBTC] preço %.2f fora [%.2f–%.2f] → fecha tudo", bid, g_lower, g_upper);
      }
      CloseOurPositions("range_break");
      CancelOurPendings();
      return;
   }

   if(InpRefillGrid)
   {
      datetime now = TimeTradeServer();
      if(now - g_lastMaintain >= 5)
      {
         g_lastMaintain = now;
         // se free voltou (posição fechou), permite log de margem de novo
         if(g_marginSkipLogged)
         {
            RefreshMarginDiag();
            int used = CountOurPendings() + CountOurPositions();
            if(g_maxAfford > used)
               g_marginSkipLogged = false;
         }
         SetupOrMaintainGrid();
      }
   }

   UpdateComment("");
}
//+------------------------------------------------------------------+
