//+------------------------------------------------------------------+
//| TrendAdvisorETH_v1.mq5                                            |
//| Nomo / ETHUSD — analisa tendência + executa 1 posição             |
//| Tendência alta → SINAL COMPRA; baixa → SINAL VENDA                |
//| Sem setup: parecer + "aguarde" | já em posição → não abre outra   |
//| v1.00: só análise                                                 |
//| v1.01: executa sinal (lote/SL/TP estilo ordem manual Nomo)        |
//+------------------------------------------------------------------+
#property copyright "Vitor / mt5-eas"
#property version   "1.01"
#property strict
#property description "ETH tendência: sinal no log + 1 ordem. Sem nova entrada se já houver posição."

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_BIAS
{
   BIAS_NONE = 0,
   BIAS_UP   = 1,
   BIAS_DN   = -1
};

enum ENUM_ADVICE
{
   ADV_WAIT = 0,
   ADV_BUY  = 1,
   ADV_SELL = -1
};

//------------------------ Inputs ------------------------------------
input group "=== Geral ==="
input ENUM_TIMEFRAMES InpTF       = PERIOD_H1;  // H1 tendência; M15 se quiser mais sinais
input long   InpMagic             = 330933;
input string InpTradeComment      = "TrendAdvETH";
input bool   InpVerboseLog        = true;
input bool   InpShowPanel         = true;
input bool   InpEnableTrading     = true;       // false = só log (modo antigo)

input group "=== Execução (como no print Nomo) ==="
input double InpLots              = 0.20;       // Volume
input int    InpStopPoints        = 4252;       // Perda máxima (~US$9 @ 0.20 no print)
input int    InpTakePoints        = 5473;       // Lucro máximo (~US$11 @ 0.20 no print)
input int    InpSlippagePoints    = 80;

input group "=== Tendência ==="
input int    InpEMAFast           = 20;
input int    InpEMASlow           = 50;
input int    InpADXPeriod         = 14;
input double InpADX_TrendMin      = 20.0;
input double InpEMA_SepMinPts     = 0.0;

input group "=== Setup conveniente (pullback) ==="
input int    InpATRPeriod         = 14;
input double InpPB_TouchATR       = 0.35;
input double InpPB_MinBodyATR     = 0.25;
input int    InpCooldownBars      = 3;

input group "=== Filtros ==="
input int    InpMaxSpreadPoints   = 0;          // 0 = ignora
input bool   InpRequireClosedBar  = true;

//------------------------ Estado ------------------------------------
int hEMAFast = INVALID_HANDLE;
int hEMASlow = INVALID_HANDLE;
int hADX     = INVALID_HANDLE;
int hATR     = INVALID_HANDLE;

datetime g_lastBar = 0;
datetime g_lastSignalBar = 0;
int      g_lastSignalDir = 0;
int      g_barsSinceSignal = 999;

ENUM_BIAS   g_bias = BIAS_NONE;
ENUM_ADVICE g_advice = ADV_WAIT;
string      g_parecer = "";
string      g_detail  = "";
double      g_emaFast = 0.0;
double      g_emaSlow = 0.0;
double      g_adx = 0.0;
double      g_atr = 0.0;

//+------------------------------------------------------------------+
string BiasName(const ENUM_BIAS b)
{
   if(b == BIAS_UP) return "ALTA";
   if(b == BIAS_DN) return "BAIXA";
   return "LATERAL";
}

//+------------------------------------------------------------------+
string AdviceName(const ENUM_ADVICE a)
{
   if(a == ADV_BUY)  return "SINAL COMPRA";
   if(a == ADV_SELL) return "SINAL VENDA";
   return "AGUARDE";
}

//+------------------------------------------------------------------+
int SpreadPoints()
{
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
}

//+------------------------------------------------------------------+
double TickSize()
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return (ts > 0.0 ? ts : _Point);
}

//+------------------------------------------------------------------+
double SnapPrice(const double price)
{
   if(price <= 0.0) return 0.0;
   double ts = TickSize();
   if(ts <= 0.0) return price;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(MathRound(price / ts) * ts, digits);
}

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
int CountOurPendings()
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   double f[], s[], adx[], atr[];
   ArraySetAsSeries(f, true);
   ArraySetAsSeries(s, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(atr, true);
   int sh = InpRequireClosedBar ? 1 : 0;
   if(CopyBuffer(hEMAFast, 0, sh, 3, f) < 3) return false;
   if(CopyBuffer(hEMASlow, 0, sh, 2, s) < 2) return false;
   if(CopyBuffer(hADX, 0, sh, 2, adx) < 2) return false;
   if(CopyBuffer(hATR, 0, sh, 2, atr) < 2) return false;
   g_emaFast = f[0];
   g_emaSlow = s[0];
   g_adx = adx[0];
   g_atr = atr[0];
   return (g_emaFast > 0.0 && g_emaSlow > 0.0 && g_atr > 0.0);
}

//+------------------------------------------------------------------+
ENUM_BIAS ClassifyBias()
{
   if(g_adx < InpADX_TrendMin)
      return BIAS_NONE;

   double sep = MathAbs(g_emaFast - g_emaSlow);
   double sepPts = (_Point > 0.0 ? sep / _Point : sep);
   if(InpEMA_SepMinPts > 0.0 && sepPts < InpEMA_SepMinPts)
      return BIAS_NONE;

   if(g_emaFast > g_emaSlow) return BIAS_UP;
   if(g_emaFast < g_emaSlow) return BIAS_DN;
   return BIAS_NONE;
}

//+------------------------------------------------------------------+
bool SetupConvenient(const ENUM_BIAS bias, string &why)
{
   why = "";
   if(bias == BIAS_NONE) return false;

   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   int sh = InpRequireClosedBar ? 1 : 0;
   if(CopyRates(_Symbol, InpTF, sh, 3, bars) < 3) return false;

   MqlRates c = bars[0];
   double body = MathAbs(c.close - c.open);
   double minBody = g_atr * InpPB_MinBodyATR;
   double touchDist = g_atr * InpPB_TouchATR;

   double nearEma = MathMin(MathAbs(c.low - g_emaFast), MathAbs(c.high - g_emaFast));
   bool touched = (c.low <= g_emaFast + touchDist && c.high >= g_emaFast - touchDist) ||
                  (nearEma <= touchDist);

   if(!touched)
   {
      why = "preço longe da EMA rápida — sem pullback";
      return false;
   }
   if(body < minBody)
   {
      why = StringFormat("corpo fraco (%.5f < %.5f)", body, minBody);
      return false;
   }

   if(bias == BIAS_UP)
   {
      if(c.close <= c.open)
      {
         why = "viés ALTA mas candle de baixa — aguarde confirmação";
         return false;
      }
      if(c.close < g_emaFast)
      {
         why = "fechou abaixo da EMA rápida — aguarde";
         return false;
      }
      why = StringFormat("pullback EMA%d + candle alta | ADX=%.1f", InpEMAFast, g_adx);
      return true;
   }

   if(c.close >= c.open)
   {
      why = "viés BAIXA mas candle de alta — aguarde confirmação";
      return false;
   }
   if(c.close > g_emaFast)
   {
      why = "fechou acima da EMA rápida — aguarde";
      return false;
   }
   why = StringFormat("pullback EMA%d + candle baixa | ADX=%.1f", InpEMAFast, g_adx);
   return true;
}

//+------------------------------------------------------------------+
bool OpenBySignal(const int dir)
{
   if(!InpEnableTrading)
   {
      Print("TA .. | trading OFF — só sinal (InpEnableTrading=false)");
      return false;
   }
   if(CountOurPositions() > 0 || CountOurPendings() > 0)
   {
      PrintFormat("TA .. | já existe posição/pendente magic=%I64d — NÃO abre outra", InpMagic);
      return false;
   }
   if(InpLots <= 0.0 || InpStopPoints <= 0 || InpTakePoints <= 0)
   {
      Print("TA .. | lote/SL/TP inválidos");
      return false;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0 || ask < bid)
   {
      Print("TA .. | cotação inválida — não executa");
      return false;
   }
   if(InpMaxSpreadPoints > 0 && SpreadPoints() > InpMaxSpreadPoints)
   {
      PrintFormat("TA .. | spread %d > %d — não executa", SpreadPoints(), InpMaxSpreadPoints);
      return false;
   }

   double point = (_Point > 0.0 ? _Point : TickSize());
   double lots = NormalizeLots(InpLots);
   double entry = (dir > 0 ? ask : bid);
   double sl = (dir > 0)
      ? SnapPrice(entry - InpStopPoints * point)
      : SnapPrice(entry + InpStopPoints * point);
   double tp = (dir > 0)
      ? SnapPrice(entry + InpTakePoints * point)
      : SnapPrice(entry - InpTakePoints * point);

   // Distância mínima de stop do broker
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minGap = (stopsLevel > 0 ? stopsLevel * point : 0.0);
   if(minGap > 0.0)
   {
      if(dir > 0)
      {
         if(entry - sl < minGap) sl = SnapPrice(entry - minGap);
         if(tp - entry < minGap) tp = SnapPrice(entry + minGap);
      }
      else
      {
         if(sl - entry < minGap) sl = SnapPrice(entry + minGap);
         if(entry - tp < minGap) tp = SnapPrice(entry - minGap);
      }
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   string cmt = StringFormat("%s|%s", InpTradeComment, (dir > 0 ? "BUY" : "SELL"));
   bool ok = (dir > 0)
      ? trade.Buy(lots, _Symbol, ask, sl, tp, cmt)
      : trade.Sell(lots, _Symbol, bid, sl, tp, cmt);

   if(ok)
   {
      PrintFormat("TA ! | EXECUTOU %s vol=%.2f @≈%.2f SL=%.2f (%d pts) TP=%.2f (%d pts) | magic=%I64d",
                  (dir > 0 ? "BUY" : "SELL"), lots, entry, sl, InpStopPoints, tp, InpTakePoints, InpMagic);
   }
   else
   {
      PrintFormat("TA .. | ordem falhou ret=%u %s", trade.ResultRetcode(), trade.ResultComment());
   }
   return ok;
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(!InpShowPanel) return;
   int pos = CountOurPositions();
   string mode = InpEnableTrading ? "OPERA (máx 1 pos)" : "SÓ ANÁLISE";
   string txt = StringFormat(
      "TrendAdvisorETH v1.01 | %s %s\n"
      "PARECER: tendência de %s\n"
      "%s\n"
      "EMA%d=%.2f  EMA%d=%.2f  ADX=%.1f  ATR=%.2f\n"
      "vol=%.2f SL=%dpts TP=%dpts | pos=%d | %s\n"
      "spread=%d | magic=%I64d\n"
      "%s",
      _Symbol, EnumToString(InpTF),
      BiasName(g_bias),
      AdviceName(g_advice),
      InpEMAFast, g_emaFast, InpEMASlow, g_emaSlow, g_adx, g_atr,
      InpLots, InpStopPoints, InpTakePoints, pos, mode,
      SpreadPoints(), InpMagic,
      g_detail
   );
   Comment(txt);
}

//+------------------------------------------------------------------+
void LogPulse(const bool isSignal)
{
   if(!InpVerboseLog && !isSignal) return;
   string prefix = isSignal ? "TA !" : "TA ..";
   PrintFormat("%s | %s | tendência=%s | %s | %s | ADX=%.1f EMA=%.2f/%.2f | pos=%d",
               prefix, _Symbol, BiasName(g_bias), AdviceName(g_advice),
               g_detail, g_adx, g_emaFast, g_emaSlow, CountOurPositions());
}

//+------------------------------------------------------------------+
void AnalyzeBar()
{
   if(!RefreshIndicators())
   {
      g_bias = BIAS_NONE;
      g_advice = ADV_WAIT;
      g_parecer = "indicadores indisponíveis";
      g_detail = "aguarde dados";
      UpdatePanel();
      return;
   }

   if(InpMaxSpreadPoints > 0 && SpreadPoints() > InpMaxSpreadPoints)
   {
      g_bias = ClassifyBias();
      g_advice = ADV_WAIT;
      g_detail = StringFormat("spread %d > %d — aguarde", SpreadPoints(), InpMaxSpreadPoints);
      g_parecer = StringFormat("tendência de %s (spread largo)", BiasName(g_bias));
      UpdatePanel();
      LogPulse(false);
      return;
   }

   g_bias = ClassifyBias();
   g_barsSinceSignal++;

   string setupWhy = "";
   bool setupOk = SetupConvenient(g_bias, setupWhy);

   if(g_bias == BIAS_NONE)
   {
      g_advice = ADV_WAIT;
      g_parecer = "mercado lateral / tendência fraca";
      g_detail = StringFormat("ADX=%.1f < %.0f — aguarde", g_adx, InpADX_TrendMin);
      UpdatePanel();
      LogPulse(false);
      return;
   }

   bool cooled = (g_barsSinceSignal >= InpCooldownBars) || (g_lastSignalDir != (int)g_bias);

   if(setupOk && cooled)
   {
      g_advice = (g_bias == BIAS_UP) ? ADV_BUY : ADV_SELL;
      g_parecer = StringFormat("tendência de %s", BiasName(g_bias));
      g_detail = setupWhy;
      g_lastSignalDir = (int)g_bias;
      g_barsSinceSignal = 0;
      g_lastSignalBar = iTime(_Symbol, InpTF, InpRequireClosedBar ? 1 : 0);
      UpdatePanel();
      LogPulse(true);

      // Executa junto com o sinal (1 posição máx.)
      if(g_advice == ADV_BUY)
         OpenBySignal(1);
      else if(g_advice == ADV_SELL)
         OpenBySignal(-1);
      UpdatePanel();
      return;
   }

   g_advice = ADV_WAIT;
   g_parecer = StringFormat("tendência de %s", BiasName(g_bias));
   if(CountOurPositions() > 0)
      g_detail = "posição aberta — aguardando SL/TP (sem nova entrada)";
   else if(setupOk && !cooled)
      g_detail = StringFormat("setup ok mas cooldown (%d/%d barras) — aguarde",
                              g_barsSinceSignal, InpCooldownBars);
   else if(StringLen(setupWhy) > 0)
      g_detail = setupWhy + " — aguarde";
   else
      g_detail = "sem setup conveniente — aguarde";

   UpdatePanel();
   LogPulse(false);
}

//+------------------------------------------------------------------+
int OnInit()
{
   Print("========== TrendAdvisorETH v1.01 ==========");
   PrintFormat("TA init | trading=%s | máx 1 posição | magic=%I64d",
               (InpEnableTrading ? "ON" : "OFF (só log)"), InpMagic);
   PrintFormat("TA init | símbolo=%s chart=%s InpTF=%s",
               _Symbol, EnumToString((ENUM_TIMEFRAMES)Period()), EnumToString(InpTF));
   PrintFormat("TA init | vol=%.2f SL=%dpts TP=%dpts | EMA %d/%d ADX>=%.0f",
               InpLots, InpStopPoints, InpTakePoints,
               InpEMAFast, InpEMASlow, InpADX_TrendMin);

   if(StringFind(_Symbol, "ETH") < 0)
      Print("TA init | AVISO: símbolo não parece ETH — pensado p/ ETHUSD");

   if(Period() != InpTF)
      PrintFormat("TA init | AVISO chart=%s ≠ InpTF=%s — arraste no gráfico %s",
                  EnumToString((ENUM_TIMEFRAMES)Period()), EnumToString(InpTF), EnumToString(InpTF));

   hEMAFast = iMA(_Symbol, InpTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMASlow = iMA(_Symbol, InpTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hADX = iADX(_Symbol, InpTF, InpADXPeriod);
   hATR = iATR(_Symbol, InpTF, InpATRPeriod);
   if(hEMAFast == INVALID_HANDLE || hEMASlow == INVALID_HANDLE ||
      hADX == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("TA init | falha ao criar indicadores");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_lastBar = 0;
   AnalyzeBar();
   Print("==========================================");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   if(hEMAFast != INVALID_HANDLE) IndicatorRelease(hEMAFast);
   if(hEMASlow != INVALID_HANDLE) IndicatorRelease(hEMASlow);
   if(hADX != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   PrintFormat("TrendAdvisorETH: deinit reason=%d", reason);
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime bar = iTime(_Symbol, InpTF, 0);
   if(bar == 0) return;
   if(bar == g_lastBar)
   {
      // Mantém painel com contagem de posição atualizada
      if(InpShowPanel) UpdatePanel();
      return;
   }
   g_lastBar = bar;
   AnalyzeBar();
}
//+------------------------------------------------------------------+
