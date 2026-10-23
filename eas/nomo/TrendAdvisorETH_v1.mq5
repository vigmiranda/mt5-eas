//+------------------------------------------------------------------+
//| TrendAdvisorETH_v1.mq5                                            |
//| Nomo / ETHUSD — SOMENTE ANÁLISE (não abre ordens)                 |
//| Tendência alta → sugere COMPRA quando conveniente                 |
//| Tendência baixa → sugere VENDA quando conveniente                 |
//| Sem setup: parecer do mercado + "aguarde"                         |
//| v1.00: M15 padrão (InpTF=M5 se quiser) | EMA+ADX+pullback         |
//+------------------------------------------------------------------+
#property copyright "Vitor / mt5-eas"
#property version   "1.00"
#property strict
#property description "Advisor ETH: analisa tendência e avisa compra/venda. NÃO opera."

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
input ENUM_TIMEFRAMES InpTF       = PERIOD_M15; // M15 padrão; use M5 se preferir
input long   InpMagic             = 330933;     // ID do advisor (não opera)
input string InpTradeComment      = "TrendAdvETH";
input bool   InpVerboseLog        = true;
input bool   InpShowPanel         = true;

input group "=== Tendência ==="
input int    InpEMAFast           = 20;
input int    InpEMASlow           = 50;
input int    InpADXPeriod         = 14;
input double InpADX_TrendMin      = 20.0;       // Abaixo = lateral / fraco
input double InpEMA_SepMinPts     = 0.0;        // 0 = desliga; senão sep. mínima EMA em pts

input group "=== Setup conveniente (pullback) ==="
input int    InpATRPeriod         = 14;
input double InpPB_TouchATR       = 0.35;       // Quão perto da EMA rápida (× ATR)
input double InpPB_MinBodyATR     = 0.25;       // Corpo da barra de sinal (× ATR)
input int    InpCooldownBars      = 3;          // Barras sem repetir o mesmo SINAL

input group "=== Filtros ==="
input int    InpMaxSpreadPoints   = 0;          // 0 = ignora
input bool   InpRequireClosedBar  = true;       // Avalia só barra fechada

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
   long spr = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (int)spr;
}

//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   double f[], s[], adx[], atr[];
   ArraySetAsSeries(f, true);
   ArraySetAsSeries(s, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(atr, true);
   // shift 1 = barra fechada
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
// Setup conveniente: barra fechada toca/volta na EMA rápida a favor do viés
bool SetupConvenient(const ENUM_BIAS bias, string &why)
{
   why = "";
   if(bias == BIAS_NONE) return false;

   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   int sh = InpRequireClosedBar ? 1 : 0;
   if(CopyRates(_Symbol, InpTF, sh, 3, bars) < 3) return false;

   MqlRates c = bars[0]; // barra de sinal (fechada se RequireClosedBar)
   double body = MathAbs(c.close - c.open);
   double minBody = g_atr * InpPB_MinBodyATR;
   double touchDist = g_atr * InpPB_TouchATR;

   // Preço interagiu com EMA rápida
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
      // Compra: candle de alta após tocar suporte EMA
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

   // Venda
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
void UpdatePanel()
{
   if(!InpShowPanel) return;
   string name = "TrendAdvETH_panel";
   string txt = StringFormat(
      "TrendAdvisorETH v1.00 | %s %s\n"
      "PARECER: tendência de %s\n"
      "%s\n"
      "EMA%d=%.2f  EMA%d=%.2f  ADX=%.1f  ATR=%.2f\n"
      "spread=%d | magic=%I64d | NÃO OPERA\n"
      "%s",
      _Symbol, EnumToString(InpTF),
      BiasName(g_bias),
      AdviceName(g_advice),
      InpEMAFast, g_emaFast, InpEMASlow, g_emaSlow, g_adx, g_atr,
      SpreadPoints(), InpMagic,
      g_detail
   );
   Comment(txt);
   // name unused — Comment suffices; keep for future ObjectCreate
   if(StringLen(name) < 0) return;
}

//+------------------------------------------------------------------+
void LogPulse(const bool isSignal)
{
   if(!InpVerboseLog && !isSignal) return;
   string prefix = isSignal ? "TA !" : "TA ..";
   PrintFormat("%s | %s | tendência=%s | %s | %s | ADX=%.1f EMA=%.2f/%.2f",
               prefix, _Symbol, BiasName(g_bias), AdviceName(g_advice),
               g_detail, g_adx, g_emaFast, g_emaSlow);
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

   // Cooldown: não repetir sinal na mesma direção
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
      return;
   }

   g_advice = ADV_WAIT;
   g_parecer = StringFormat("tendência de %s", BiasName(g_bias));
   if(setupOk && !cooled)
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
   Print("========== TrendAdvisorETH v1.00 ==========");
   Print("TA init | SOMENTE ANÁLISE — este EA NÃO envia ordens");
   PrintFormat("TA init | símbolo=%s chart=%s InpTF=%s | magic=%I64d",
               _Symbol, EnumToString((ENUM_TIMEFRAMES)Period()), EnumToString(InpTF), InpMagic);
   PrintFormat("TA init | EMA %d/%d | ADX>=%.0f | pullback ATR×%.2f | cooldown=%d barras",
               InpEMAFast, InpEMASlow, InpADX_TrendMin, InpPB_TouchATR, InpCooldownBars);

   if(StringFind(_Symbol, "ETH") < 0)
      Print("TA init | AVISO: símbolo não parece ETH — advisor pensado p/ ETHUSD");

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
   if(bar == g_lastBar) return; // 1× por barra — sem spam de tick
   g_lastBar = bar;
   AnalyzeBar();
}
//+------------------------------------------------------------------+
