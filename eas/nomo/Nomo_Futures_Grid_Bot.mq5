//+------------------------------------------------------------------+
//| Nomo_Futures_Grid_Bot.mq5                                        |
//| EXPERIMENTAL — conflita com REGRAS (sem grid / 1 posição)        |
//| Uso: teste Nomo BTCUSD com conta ~US$300 | lote 0.01 | 5–8 níveis|
//| v1.00: faixa auto ±%, TP por nível, cancel/close seguros         |
//+------------------------------------------------------------------+
#property copyright "Vitor / mt5-eas (experimental)"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

input group "=== EXPERIMENTAL / risco conta pequena ==="
input double   InpLotSize       = 0.01;   // Lote por nível (mínimo Nomo)
input int      InpGridLevels    = 6;      // Níveis (recomendado 5–8; máx forçado 8)
input double   InpRangePct      = 3.0;    // Faixa total ±% em torno do preço (curta)
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
bool MarginOk(const ENUM_ORDER_TYPE type, const double lots, const double price)
{
   double margin = 0.0;
   if(!OrderCalcMargin(type, _Symbol, lots, price, margin))
      return true; // se broker não calcular, não bloqueia
   double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   return (margin > 0.0 && free > margin * 1.2);
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
      if(half <= 0.0) half = 0.03;
      // faixa total ≈ 2*half (ex.: 3% => ±1.5% se quiséssemos; aqui RangePct = semi-amplitude)
      // Interpretação do guia: limites a 3% ou 5% de distância → usamos ± RangePct
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
   if(g_levels > 8) g_levels = 8; // teto da recomendação US$300

   g_step = (g_upper - g_lower) / g_levels;
   if(g_step <= 0.0) return false;
   return true;
}

//+------------------------------------------------------------------+
// TP: um passo de grid a favor (realiza no nível vizinho)
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
void PlaceBuyLimit(const double price)
{
   double lots = NormalizeLots(InpLotSize);
   double px = SnapPrice(price);
   if(px <= 0.0 || lots <= 0.0) return;
   if(HasPendingNear(px, ORDER_TYPE_BUY_LIMIT)) return;
   if(HasPositionNear(px, POSITION_TYPE_BUY)) return;
   if(!MarginOk(ORDER_TYPE_BUY_LIMIT, lots, px))
   {
      if(InpVerboseLog)
         PrintFormat("[GridBTC] margem insuficiente BuyLimit @ %.2f", px);
      return;
   }

   double tp = TpForBuy(px);
   if(tp <= px) tp = 0.0;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpMaxSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   if(!trade.BuyLimit(lots, px, _Symbol, 0.0, tp, ORDER_TIME_GTC, 0, InpCommentBuy))
      PrintFormat("[GridBTC] BuyLimit falhou @ %.2f ret=%u %s", px, trade.ResultRetcode(), trade.ResultComment());
   else if(InpVerboseLog)
      PrintFormat("[GridBTC] BuyLimit %.2f lot=%.2f tp=%.2f", px, lots, tp);
}

//+------------------------------------------------------------------+
void PlaceSellLimit(const double price)
{
   double lots = NormalizeLots(InpLotSize);
   double px = SnapPrice(price);
   if(px <= 0.0 || lots <= 0.0) return;
   if(HasPendingNear(px, ORDER_TYPE_SELL_LIMIT)) return;
   if(HasPositionNear(px, POSITION_TYPE_SELL)) return;
   if(!MarginOk(ORDER_TYPE_SELL_LIMIT, lots, px))
   {
      if(InpVerboseLog)
         PrintFormat("[GridBTC] margem insuficiente SellLimit @ %.2f", px);
      return;
   }

   double tp = TpForSell(px);
   if(tp >= px || tp <= 0.0) tp = 0.0;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpMaxSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   if(!trade.SellLimit(lots, px, _Symbol, 0.0, tp, ORDER_TIME_GTC, 0, InpCommentSell))
      PrintFormat("[GridBTC] SellLimit falhou @ %.2f ret=%u %s", px, trade.ResultRetcode(), trade.ResultComment());
   else if(InpVerboseLog)
      PrintFormat("[GridBTC] SellLimit %.2f lot=%.2f tp=%.2f", px, lots, tp);
}

//+------------------------------------------------------------------+
void SetupOrMaintainGrid()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0) return;

   for(int i = 0; i <= g_levels; i++)
   {
      double level = SnapPrice(g_lower + i * g_step);
      if(level <= g_lower - g_step * 0.01) continue;
      if(level >= g_upper + g_step * 0.01) continue;

      if(level < bid - g_step * 0.05)
         PlaceBuyLimit(level);
      else if(level > bid + g_step * 0.05)
         PlaceSellLimit(level);
   }
}

//+------------------------------------------------------------------+
void UpdateComment(const string extra = "")
{
   string txt = StringFormat(
      "GridBTC EXP v1.00 | %s\nfaixa %.0f–%.0f | step %.1f | níveis %d | lot %.2f\npend=%d pos=%d | magic %I64d\n%s",
      _Symbol, g_lower, g_upper, g_step, g_levels, NormalizeLots(InpLotSize),
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

   PrintFormat("[GridBTC] init %s | upper=%.2f lower=%.2f step=%.2f levels=%d lot=%.2f magic=%I64d | freeMargin=%.2f",
               _Symbol, g_upper, g_lower, g_step, g_levels, NormalizeLots(InpLotSize), InpMagic,
               AccountInfoDouble(ACCOUNT_MARGIN_FREE));

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
      if(now - g_lastMaintain >= 5) // evita spam de OrderSend
      {
         g_lastMaintain = now;
         SetupOrMaintainGrid();
      }
   }

   UpdateComment("");
}
//+------------------------------------------------------------------+
