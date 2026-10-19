//+------------------------------------------------------------------+
//| RegimeRouterWIN_v1.mq5                                            |
//| Clear / WIN — roteador de estratégias (único EA ativo)            |
//| Cascata M5: OB → Pullback → PreçoMédio (flags on/off)            |
//| Lock: 1 estratégia dona até flat (PM pode abrir pernas)          |
//| OB sem indício → libera demais ANTES das 11h                     |
//| STOP DIA 5% | sem meta de lucro / sem preferência 1 trade        |
//| v1.04: cascata + flags + aborto cedo OB                          |
//| v1.05: log M5 abreviado (2 linhas) + telinha enxuta              |
//+------------------------------------------------------------------+
#property copyright "Vitor / mt5-eas"
#property version   "1.05"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_REGIME
{
   REG_UNKNOWN = 0,
   REG_R1_ABERTURA_OK = 1,
   REG_R2_EXPLOSIVA = 2,
   REG_R3_TENDENCIA = 3,
   REG_R4_LATERAL = 4,
   REG_RISCO_DIA = 5,
   REG_FORA = 6
};

enum ENUM_MODULE
{
   MOD_NONE = 0,
   MOD_OPENBREAK = 1,
   MOD_PULLBACK = 2,
   MOD_MEANREV = 3
};

//------------------------ Inputs ------------------------------------
input group "=== Volume / capital virtual ==="
input double InpClearSaldo        = 4538.48;  // Saldo Clear atual
input double InpFixedVolume       = 1.0;      // OB/Pullback: contratos fixos
input double InpMaxVolume         = 10.0;
input bool   InpEstimateFees      = true;
input double InpFeePerSide        = 0.25;
input bool   InpIncludeFloating   = true;
input bool   InpResetVirtualSeed  = false;
input bool   InpSaveDayHistory    = true;
input string InpHistoryFile       = "RegimeRouterWIN_v1_equity.csv";

input group "=== Risco único do dia ==="
input double InpStopDiaPct        = 5.0;      // STOP DIA absoluto (todos os módulos)
input bool   InpFlatOnDailyLoss   = true;
input int    InpMaxTradesDay      = 8;        // Teto de segurança (não é meta / não é “1 trade”)
input int    InpMaxSpreadPoints   = 40;

input group "=== Estratégias (ligar / desligar) ==="
input bool   InpEnableOpenBreak   = true;     // A — OpenBreak (abertura)
input bool   InpEnablePullback    = true;     // B — Pullback (tendência)
input bool   InpEnablePrecoMedio  = true;     // C — Preço médio (lateral)

input group "=== Caixa abertura (R1/R2) ==="
input int    InpBoxStartH         = 9;
input int    InpBoxStartM         = 0;
input int    InpBoxEndH           = 9;
input int    InpBoxEndM           = 15;
input double InpMinBoxPts         = 80.0;
input double InpMaxBoxPts         = 1200.0;

input group "=== Módulo OpenBreak (R1 manhã) ==="
input int    InpOB_EntryEndH      = 10;
input int    InpOB_EntryEndM      = 30;
input int    InpOB_FlatH          = 11;
input int    InpOB_FlatM          = 0;
input int    InpOB_BreakBufferPts = 20;
input bool   InpOB_UseVolume      = true;
input double InpOB_VolMinX        = 1.00;
input int    InpOB_BE_Points      = 150;
input int    InpOB_BE_LockPts     = 20;
input double InpOB_TrailStartATR  = 0.80;
input double InpOB_TrailATR       = 0.50;

input group "=== Sessão B/C e flat ==="
input int    InpAftStartH         = 11;       // reservado (cascata B/C inicia após aborto OB / fim caixa)
input int    InpAftStartM         = 5;
input int    InpAftEndH           = 15;       // fim sessão B/C
input int    InpAftEndM           = 45;
input int    InpFlatH             = 16;
input int    InpFlatM             = 0;

input group "=== Classificação R3 / R4 ==="
input int    InpEMAFast           = 20;
input int    InpEMASlow           = 50;
input int    InpADXPeriod         = 14;
input double InpADX_TrendMin      = 20.0;     // R3
input double InpADX_LateralMax    = 18.0;     // R4
input double InpEMA_SepMinPts     = 80.0;     // Separação mínima EMA20-50 p/ R3
input int    InpATRPeriod         = 14;

input group "=== Módulo Pullback (R3) ==="
input double InpPB_RewardRisk     = 2.0;
input int    InpPB_BufferPts      = 10;
input int    InpPB_EntryOffsetPts = 5;
input int    InpPB_MinRiskPts     = 80;
input int    InpPB_MaxRiskPts     = 500;

input group "=== Módulo R4 Preço Médio (lateral) ==="
input int    InpMR_BBPeriod       = 20;
input double InpMR_BBDev          = 2.0;
input int    InpMR_MinBandPts     = 60;       // Banda muito estreita = skip
input int    InpPM_MaxLegs        = 3;        // Máx. pernas do pacote
input double InpPM_CycleStopBRL   = 120.0;    // Stop financeiro do ciclo R4
input double InpPM_ATR_SpaceMult  = 0.50;     // Espaço entre pernas = ATR × mult
input int    InpPM_SpaceMinPts    = 100;      // Piso espaçamento
input int    InpPM_SpaceMaxPts    = 200;      // Teto espaçamento
input int    InpPM_MinGainPts     = 40;       // Alvo mínimo além do médio
input double InpPM_LotBand2Cap    = 6500.0;   // Capital ≥ → 2 minis/perna
input double InpPM_LotBand3Cap    = 8500.0;   // Capital ≥ → 3 minis/perna
input double InpPM_MaxLotsPerLeg  = 3.0;      // Teto duro por perna

input group "=== Geral ==="
input ENUM_TIMEFRAMES InpTF       = PERIOD_M5;
input long   InpMagic             = 260920;   // Único — EA ativo Clear
input int    InpSlippagePoints    = 30;
input string InpTradeComment      = "RegimeRouterWIN";
input bool   InpVerboseLog        = true;

//------------------------ Estado ------------------------------------
datetime g_dayStart = 0;
double   g_dayStartEquity = 0.0;
datetime g_lastBarOB = 0;
datetime g_lastBarAft = 0;
datetime g_lastStatusBar = 0; // pulse de log a cada M5
bool     g_dayStopped = false;
bool     g_loggedDailyFlat = false;
int      g_tradesToday = 0;
int      g_tradesOB = 0;
int      g_tradesPB = 0;
int      g_tradesMR = 0;

double   g_seedCapital = 0.0;
double   g_realizedAll = 0.0;
double   g_feesAll = 0.0;
datetime g_equityEpoch = 0;
string   g_capitalSource = "virtual";

// Caixa
double   g_boxHigh = 0.0;
double   g_boxLow  = 0.0;
double   g_boxPts  = 0.0;
bool     g_boxReady = false;
bool     g_boxLogged = false;
bool     g_r2Day = false;          // abertura explosiva/inválida

// Regime / UI / cascata
ENUM_REGIME g_regime = REG_UNKNOWN;
ENUM_REGIME g_regimeLogged = REG_UNKNOWN;
ENUM_MODULE g_activeMod = MOD_NONE;
ENUM_MODULE g_lockedMod = MOD_NONE; // dona da posição até flat
bool     g_obAborted = false;       // OB sem indício / janela acabou → libera B/C
string   g_obAbortWhy = "";
bool     g_obAbortLogged = false;
string   g_regimeWhy = "";
string   g_lastAction = "";
string   g_lastSkip = "";
datetime g_lastSkipLog = 0;

// OpenBreak gestão
bool     g_beDone = false;

// R4 preço médio (pacote)
bool     g_pmActive = false;
int      g_pmDir = 0;          // +1 buy / -1 sell
int      g_pmLegs = 0;
double   g_pmAvg = 0.0;
double   g_pmLastPrice = 0.0;
double   g_pmLotPerLeg = 1.0;
bool     g_pmCycleCounted = false; // já contou em g_tradesMR/Today

// Pullback sinal
int      g_pbDir = 0;
datetime g_pbSignalBar = 0;
double   g_pbHigh = 0.0;
double   g_pbLow = 0.0;
bool     g_pbConsumed = false;

// Indicadores runtime
double   g_emaFast = 0.0;
double   g_emaSlow = 0.0;
double   g_adx = 0.0;
double   g_atrPts = 0.0;
double   g_bbUpper = 0.0;
double   g_bbMid = 0.0;
double   g_bbLower = 0.0;

int hEMAFast = INVALID_HANDLE;
int hEMASlow = INVALID_HANDLE;
int hADX = INVALID_HANDLE;
int hATR = INVALID_HANDLE;
int hVol = INVALID_HANDLE;
int hBB = INVALID_HANDLE;

//+------------------------------------------------------------------+
string RegimeName(const ENUM_REGIME r)
{
   switch(r)
   {
      case REG_R1_ABERTURA_OK: return "R1_ABERTURA_OK";
      case REG_R2_EXPLOSIVA:   return "R2_EXPLOSIVA";
      case REG_R3_TENDENCIA:   return "R3_TENDENCIA";
      case REG_R4_LATERAL:     return "R4_LATERAL";
      case REG_RISCO_DIA:      return "RISCO_DIA";
      case REG_FORA:           return "FORA";
      default:                 return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
// Abreviações curtas p/ log Experts (coluna Mensagem é estreita)
string RegimeAbbr(const ENUM_REGIME r)
{
   switch(r)
   {
      case REG_R1_ABERTURA_OK: return "R1";
      case REG_R2_EXPLOSIVA:   return "R2";
      case REG_R3_TENDENCIA:   return "R3";
      case REG_R4_LATERAL:     return "R4";
      case REG_RISCO_DIA:      return "STOP";
      case REG_FORA:           return "FORA";
      default:                 return "?";
   }
}

//+------------------------------------------------------------------+
string ModuleName(const ENUM_MODULE m)
{
   switch(m)
   {
      case MOD_OPENBREAK: return "OpenBreak";
      case MOD_PULLBACK:  return "Pullback";
      case MOD_MEANREV:   return "PrecoMedio";
      default:            return "nenhum";
   }
}

//+------------------------------------------------------------------+
string ModuleAbbr(const ENUM_MODULE m)
{
   switch(m)
   {
      case MOD_OPENBREAK: return "OB";
      case MOD_PULLBACK:  return "PB";
      case MOD_MEANREV:   return "PM";
      default:            return "-";
   }
}

//+------------------------------------------------------------------+
string ClipStr(const string s, const int maxLen)
{
   if(maxLen <= 3 || StringLen(s) <= maxLen) return s;
   return StringSubstr(s, 0, maxLen - 1) + "…";
}

//+------------------------------------------------------------------+
void LogWhy(const string msg)
{
   g_lastAction = msg;
   if(InpVerboseLog)
      PrintFormat("RR ! | %s", ClipStr(msg, 90));
}

//+------------------------------------------------------------------+
void LogSkip(const string msg)
{
   g_lastSkip = msg;
   // Skip só no pulse M5 (evita spam); guarda texto p/ linha 2
}

//+------------------------------------------------------------------+
// Log a cada nova barra M5 — igual ao acompanhamento antigo (5 em 5 min)
void LogBarPulse(const datetime now)
{
   datetime bar0 = iTime(_Symbol, InpTF, 0);
   if(bar0 == 0 || bar0 == g_lastStatusBar)
      return;
   g_lastStatusBar = bar0;

   if(!InpVerboseLog)
      return;

   // Decisão curta (MT5 Experts não quebra linha bem — usamos 2 Prints + abrev)
   string dec = "";
   if(g_dayStopped || g_regime == REG_RISCO_DIA)
      dec = "STOP";
   else if(g_lockedMod != MOD_NONE && (CountOurPositions() > 0 || g_pmActive))
      dec = StringFormat("LOCK-%s", ModuleAbbr(g_lockedMod));
   else if(g_activeMod == MOD_NONE)
      dec = "IDLE";
   else if(CountOurPositions() > 0)
      dec = "POS";
   else if(g_tradesToday >= InpMaxTradesDay)
      dec = "MAX";
   else
      dec = StringFormat("WAIT-%s", ModuleAbbr(g_activeMod));

   string boxTag = (!g_boxReady ? "…" : (g_r2Day ? "R2" : "OK"));
   string why = ClipStr(g_regimeWhy, 56);
   string det = ClipStr((g_lastSkip != "" ? g_lastSkip : g_lastAction), 56);

   // Linha 1: estado | Linha 2: motivo/detalhe (equivale a “quebra” no Experts)
   PrintFormat("RR %s | %s %s | %s | cx=%.0f(%s) ADX=%.0f dPnL=%.0f t=%d/%d [%d|%d|%d]",
               TimeToString(bar0, TIME_MINUTES),
               RegimeAbbr(g_regime), ModuleAbbr(g_activeMod), dec,
               g_boxPts, boxTag, g_adx, DayPnLMoney(),
               g_tradesToday, InpMaxTradesDay, g_tradesOB, g_tradesPB, g_tradesMR);
   PrintFormat("RR .. | %s | %s", why, det);
}

//+------------------------------------------------------------------+
double ClampVolume(const double v)
{
   double vol = MathMax(0.0, v);
   vol = MathMin(vol, InpMaxVolume);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 1.0;
   vol = MathFloor(vol / step + 1e-8) * step;
   if(vol < vmin) vol = 0.0;
   if(vol > vmax) vol = vmax;
   return vol;
}

//+------------------------------------------------------------------+
double CalcVolume() { return ClampVolume(InpFixedVolume); }

//+------------------------------------------------------------------+
// Lote R4 por faixa de capital (mesma qtd em todas as pernas — sem dobrar)
double R4LotsPerLeg()
{
   double cap = GetCapital();
   double lots = 1.0;
   if(cap >= InpPM_LotBand3Cap) lots = 3.0;
   else if(cap >= InpPM_LotBand2Cap) lots = 2.0;
   lots = MathMin(lots, InpPM_MaxLotsPerLeg);
   return ClampVolume(lots);
}

//+------------------------------------------------------------------+
double PM_SpacePts()
{
   double space = g_atrPts * InpPM_ATR_SpaceMult;
   if(space < InpPM_SpaceMinPts) space = InpPM_SpaceMinPts;
   if(space > InpPM_SpaceMaxPts) space = InpPM_SpaceMaxPts;
   return space;
}

//+------------------------------------------------------------------+
void PM_Reset()
{
   g_pmActive = false;
   g_pmDir = 0;
   g_pmLegs = 0;
   g_pmAvg = 0.0;
   g_pmLastPrice = 0.0;
   g_pmLotPerLeg = 1.0;
   g_pmCycleCounted = false;
}

//+------------------------------------------------------------------+
void PM_SyncFromPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long typ = PositionGetInteger(POSITION_TYPE);
      g_pmDir = (typ == POSITION_TYPE_BUY ? 1 : -1);
      g_pmAvg = PositionGetDouble(POSITION_PRICE_OPEN);
      g_pmLastPrice = g_pmAvg; // fallback; pernas usam last add
      return;
   }
}

//+------------------------------------------------------------------+
int CurrentSpreadPoints()
{
   long spr = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spr > 0) return (int)spr;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0 || _Point <= 0.0) return 0;
   return (int)MathRound((ask - bid) / _Point);
}

//+------------------------------------------------------------------+
int MinStopDistancePoints()
{
   int stops = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax(1, MathMax(stops, freeze));
}

//+------------------------------------------------------------------+
bool IsWinSymbol()
{
   string s = _Symbol;
   StringToUpper(s);
   return (StringFind(s, "WIN") >= 0);
}

//+------------------------------------------------------------------+
int MinutesOfDay(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.hour * 60 + dt.min;
}

//+------------------------------------------------------------------+
int HM(const int h, const int m) { return h * 60 + m; }

//+------------------------------------------------------------------+
bool InMorningOBEntry(const datetime t)
{
   int n = MinutesOfDay(t);
   return (n >= HM(InpBoxEndH, InpBoxEndM) && n < HM(InpOB_EntryEndH, InpOB_EntryEndM));
}

//+------------------------------------------------------------------+
bool InAfternoon(const datetime t)
{
   int n = MinutesOfDay(t);
   return (n >= HM(InpAftStartH, InpAftStartM) && n < HM(InpAftEndH, InpAftEndM));
}

//+------------------------------------------------------------------+
bool ShouldFlatDay(const datetime t)
{
   return (MinutesOfDay(t) >= HM(InpFlatH, InpFlatM));
}

//+------------------------------------------------------------------+
bool ShouldFlatOBPosition(const datetime t)
{
   return (MinutesOfDay(t) >= HM(InpOB_FlatH, InpOB_FlatM));
}

//+------------------------------------------------------------------+
string GVPrefix() { return StringFormat("RegimeRouterWIN_v103_%I64d_", InpMagic); }

//+------------------------------------------------------------------+
// MT5 costuma guardar InpClearSaldo antigo no gráfico (5353.45).
// Se input/GV ainda for a semente legada, aplica o saldo Clear atual.
double ResolveClearSeed()
{
   const double kTarget = 4538.48;
   const double kLegacy = 5353.45;
   double seed = InpClearSaldo;
   if(MathAbs(seed - kLegacy) < 0.05)
   {
      PrintFormat("Router: InpClearSaldo ainda R$%.2f (salvo no gráfico) → forçando R$%.2f", seed, kTarget);
      seed = kTarget;
   }
   return seed;
}

//+------------------------------------------------------------------+
void EnsureSeedCapital()
{
   string keySeed = GVPrefix() + "seed";
   string keyEpoch = GVPrefix() + "epoch";
   const double kLegacy = 5353.45;
   double wanted = ResolveClearSeed();

   bool miss = (InpResetVirtualSeed || !GlobalVariableCheck(keySeed) || !GlobalVariableCheck(keyEpoch));
   if(!miss)
   {
      double stored = GlobalVariableGet(keySeed);
      // só remigra automaticamente a semente legada 5353.45
      if(MathAbs(stored - kLegacy) < 0.05)
      {
         miss = true;
         PrintFormat("Router: GV ainda com semente legada R$%.2f → R$%.2f", stored, wanted);
      }
   }

   if(miss)
   {
      g_seedCapital = wanted;
      g_equityEpoch = TimeTradeServer();
      GlobalVariableSet(keySeed, g_seedCapital);
      GlobalVariableSet(keyEpoch, (double)g_equityEpoch);
      LogWhy(StringFormat("semente capital R$%.2f época %s (input chart=R$%.2f)",
                          g_seedCapital, TimeToString(g_equityEpoch, TIME_DATE|TIME_MINUTES),
                          InpClearSaldo));
   }
   else
   {
      g_seedCapital = GlobalVariableGet(keySeed);
      g_equityEpoch = (datetime)GlobalVariableGet(keyEpoch);
   }
}

//+------------------------------------------------------------------+
double FloatingPnLOurs()
{
   double pnl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

//+------------------------------------------------------------------+
void CalcRealizedAndFeesSinceEpoch(double &pnlOut, double &feesOut)
{
   pnlOut = 0.0;
   feesOut = 0.0;
   EnsureSeedCapital();
   datetime from = g_equityEpoch;
   if(!HistorySelect(from, TimeTradeServer() + 1)) return;

   double commissionSum = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      datetime td = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(td < from) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      double vol = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double comm = HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      if(InpEstimateFees && InpFeePerSide > 0.0 &&
         (entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_OUT ||
          entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY))
         feesOut += InpFeePerSide * MathMax(vol, 1.0);

      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         pnlOut += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP) + comm;
         commissionSum += comm;
      }
   }
   if(InpEstimateFees && MathAbs(commissionSum) >= 0.01)
      feesOut = 0.0;
}

//+------------------------------------------------------------------+
double GetCapital()
{
   EnsureSeedCapital();
   double pnl, fees;
   CalcRealizedAndFeesSinceEpoch(pnl, fees);
   g_realizedAll = pnl;
   g_feesAll = fees;
   double cap = g_seedCapital + pnl - fees;
   if(InpIncludeFloating) cap += FloatingPnLOurs();
   g_capitalSource = "virtual";
   return MathMax(0.0, cap);
}

//+------------------------------------------------------------------+
double DailyLossLimitMoney()
{
   double base = (g_dayStartEquity > 0.0 ? g_dayStartEquity : GetCapital());
   return base * MathAbs(InpStopDiaPct) / 100.0;
}

//+------------------------------------------------------------------+
double DayPnLMoney()
{
   if(!HistorySelect(g_dayStart, TimeTradeServer() + 1))
      return FloatingPnLOurs();
   double pnl = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
         continue;
      pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT)
           + HistoryDealGetDouble(ticket, DEAL_SWAP)
           + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }
   return pnl + FloatingPnLOurs();
}

//+------------------------------------------------------------------+
bool DailyLossHit()
{
   return (DayPnLMoney() <= -DailyLossLimitMoney());
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
double TickSize()
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return (ts > 0.0 ? ts : _Point);
}

//+------------------------------------------------------------------+
double SnapPrice(const double price)
{
   double ts = TickSize();
   if(ts <= 0.0) return price;
   return NormalizeDouble(MathRound(price / ts) * ts, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
void NormalizeSLTP(const bool isBuy, const double price, double &sl, double &tp)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double minGap = MinStopDistancePoints() * _Point;
   if(isBuy)
   {
      if(sl > 0.0 && (price - sl) < minGap) sl = price - minGap;
      if(tp > 0.0 && (tp - price) < minGap) tp = price + minGap;
   }
   else
   {
      if(sl > 0.0 && (sl - price) < minGap) sl = price + minGap;
      if(tp > 0.0 && (price - tp) < minGap) tp = price - minGap;
   }
   if(sl > 0.0) sl = NormalizeDouble(SnapPrice(sl), digits);
   if(tp > 0.0) tp = NormalizeDouble(SnapPrice(tp), digits);
}

//+------------------------------------------------------------------+
void CloseAllOurs(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(trade.PositionClose(ticket))
         LogWhy(StringFormat("CLOSE ticket=%I64u motivo=%s", ticket, reason));
      else
         PrintFormat("Router: close falhou %I64u ret=%u (%s)", ticket, trade.ResultRetcode(), reason);
   }
}

//+------------------------------------------------------------------+
void AppendDayHistory()
{
   if(!InpSaveDayHistory || g_dayStart <= 0) return;
   string path = InpHistoryFile;
   int h = FileOpen(path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
      h = FileOpen(path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   if(FileTell(h) == 0)
      FileWriteString(h, "day,dayStartCap,dayPnL,regimeFinal,tradesOB,tradesPB,tradesMR\n");
   FileWriteString(h, StringFormat("%s,%.2f,%.2f,%s,%d,%d,%d\n",
                                   TimeToString(g_dayStart, TIME_DATE),
                                   g_dayStartEquity, DayPnLMoney(), RegimeName(g_regime),
                                   g_tradesOB, g_tradesPB, g_tradesMR));
   FileClose(h);
}

//+------------------------------------------------------------------+
void ResetDayIfNeeded()
{
   datetime now = TimeTradeServer();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   datetime day0 = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
   if(g_dayStart == day0) return;

   if(g_dayStart > 0) AppendDayHistory();

   g_dayStart = day0;
   g_dayStartEquity = GetCapital();
   g_dayStopped = false;
   g_loggedDailyFlat = false;
   g_tradesToday = 0;
   g_tradesOB = 0;
   g_tradesPB = 0;
   g_tradesMR = 0;
   g_boxHigh = g_boxLow = g_boxPts = 0.0;
   g_boxReady = g_boxLogged = g_r2Day = false;
   g_regime = REG_UNKNOWN;
   g_regimeLogged = REG_UNKNOWN;
   g_activeMod = MOD_NONE;
   g_lockedMod = MOD_NONE;
   g_obAborted = false;
   g_obAbortWhy = "";
   g_obAbortLogged = false;
   g_regimeWhy = "aguardando caixa 09:00-09:15";
   g_lastAction = "novo dia";
   g_lastSkip = "";
   g_beDone = false;
   g_pbDir = 0;
   g_pbConsumed = false;
   g_lastBarOB = 0;
   g_lastBarAft = 0;
   g_lastStatusBar = 0;
   PM_Reset();

   LogWhy(StringFormat("NOVO DIA | capital start R$%.2f | STOP DIA %.1f%% = R$%.0f | flags OB=%s PB=%s PM=%s | R4 lote/perna=%.0f magic=%I64d",
                       g_dayStartEquity, InpStopDiaPct, DailyLossLimitMoney(),
                       (InpEnableOpenBreak ? "ON" : "OFF"),
                       (InpEnablePullback ? "ON" : "OFF"),
                       (InpEnablePrecoMedio ? "ON" : "OFF"),
                       R4LotsPerLeg(), InpMagic));
}

//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   double f[1], s[1], adx[1], atr[1];
   double bu[1], bm[1], bl[1];
   if(CopyBuffer(hEMAFast, 0, 1, 1, f) < 1) return false;
   if(CopyBuffer(hEMASlow, 0, 1, 1, s) < 1) return false;
   if(CopyBuffer(hADX, 0, 1, 1, adx) < 1) return false;
   if(CopyBuffer(hATR, 0, 1, 1, atr) < 1) return false;
   if(CopyBuffer(hBB, 1, 1, 1, bu) < 1) return false; // upper
   if(CopyBuffer(hBB, 0, 1, 1, bm) < 1) return false; // middle
   if(CopyBuffer(hBB, 2, 1, 1, bl) < 1) return false; // lower

   g_emaFast = f[0];
   g_emaSlow = s[0];
   g_adx = adx[0];
   g_atrPts = (_Point > 0.0 ? atr[0] / _Point : atr[0]);
   g_bbUpper = bu[0];
   g_bbMid = bm[0];
   g_bbLower = bl[0];
   return true;
}

//+------------------------------------------------------------------+
void BuildOrUpdateBox(const datetime now)
{
   if(g_boxReady) return;

   int mins = MinutesOfDay(now);
   if(mins < HM(InpBoxStartH, InpBoxStartM))
   {
      g_regimeWhy = "pré-abertura — aguardando 09:00";
      return;
   }

   datetime from = g_dayStart + HM(InpBoxStartH, InpBoxStartM) * 60;
   datetime to   = g_dayStart + HM(InpBoxEndH, InpBoxEndM) * 60;
   datetime toScan = (mins >= HM(InpBoxEndH, InpBoxEndM) ? to : now);
   if(toScan <= from) return;

   double hi = 0.0, lo = 0.0;
   bool any = false;
   int bars = Bars(_Symbol, InpTF);
   for(int i = 0; i < bars; i++)
   {
      datetime bt = iTime(_Symbol, InpTF, i);
      if(bt == 0) break;
      if(bt >= to) continue;
      if(bt < from) break;
      double h = iHigh(_Symbol, InpTF, i);
      double l = iLow(_Symbol, InpTF, i);
      if(!any) { hi = h; lo = l; any = true; }
      else { if(h > hi) hi = h; if(l < lo) lo = l; }
   }
   if(!any) return;

   g_boxHigh = SnapPrice(hi);
   g_boxLow  = SnapPrice(lo);
   g_boxPts  = (_Point > 0.0 ? (g_boxHigh - g_boxLow) / _Point : (g_boxHigh - g_boxLow));

   if(mins < HM(InpBoxEndH, InpBoxEndM))
   {
      g_regimeWhy = StringFormat("montando caixa… parcial %.0f–%.0f (%.0f pts)", g_boxLow, g_boxHigh, g_boxPts);
      return;
   }

   g_boxReady = true;
   if(g_boxPts < InpMinBoxPts || g_boxPts > InpMaxBoxPts)
   {
      g_r2Day = true;
      if(!g_boxLogged)
      {
         g_boxLogged = true;
         LogWhy(StringFormat("CAIXA INVÁLIDA → R2_EXPLOSIVA | %.0f–%.0f = %.0f pts (limite %.0f–%.0f) | OpenBreak BLOQUEADO o dia",
                             g_boxLow, g_boxHigh, g_boxPts, InpMinBoxPts, InpMaxBoxPts));
      }
   }
   else if(!g_boxLogged)
   {
      g_boxLogged = true;
      LogWhy(StringFormat("CAIXA OK → R1 possível | %.0f–%.0f = %.0f pts | OpenBreak liberado até %02d:%02d",
                          g_boxLow, g_boxHigh, g_boxPts, InpOB_EntryEndH, InpOB_EntryEndM));
   }
}

//+------------------------------------------------------------------+
// Sessão em que B/C podem rodar (após caixa; OB liberado ou janela A esgotada)
bool InCascadeSession(const datetime t)
{
   int n = MinutesOfDay(t);
   if(n < HM(InpBoxEndH, InpBoxEndM)) return false;
   if(n >= HM(InpAftEndH, InpAftEndM)) return false;
   if(ShouldFlatDay(t)) return false;
   return true;
}

//+------------------------------------------------------------------+
void MarkOBAbort(const string why)
{
   g_obAborted = true;
   g_obAbortWhy = why;
   if(!g_obAbortLogged)
   {
      g_obAbortLogged = true;
      LogWhy(StringFormat("OB ABORTADO → libera cascata B/C | %s", why));
   }
}

//+------------------------------------------------------------------+
void UpdateOpenBreakAbort(const datetime now)
{
   if(g_obAborted) return;

   if(!InpEnableOpenBreak)
   {
      MarkOBAbort("flag OpenBreak OFF");
      return;
   }
   if(g_r2Day)
   {
      MarkOBAbort(StringFormat("caixa inválida %.0f pts (R2) — sem ORB", g_boxPts));
      return;
   }
   if(g_tradesOB > 0)
   {
      MarkOBAbort("OpenBreak já operou hoje");
      return;
   }
   if(g_boxReady && MinutesOfDay(now) >= HM(InpOB_EntryEndH, InpOB_EntryEndM))
   {
      MarkOBAbort(StringFormat("janela OB encerrada %02d:%02d sem entrada", InpOB_EntryEndH, InpOB_EntryEndM));
      return;
   }
}

//+------------------------------------------------------------------+
bool OpenBreakReleased()
{
   return g_obAborted || !InpEnableOpenBreak || g_r2Day || g_tradesOB > 0;
}

//+------------------------------------------------------------------+
bool PatternTrendStrong(string &why)
{
   if(!RefreshIndicators()) { why = "indicadores indisponíveis"; return false; }
   double emaSep = MathAbs(g_emaFast - g_emaSlow);
   double emaSepPts = (_Point > 0.0 ? emaSep / _Point : emaSep);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool trendUp = (g_emaFast > g_emaSlow && bid > g_emaFast);
   bool trendDn = (g_emaFast < g_emaSlow && bid < g_emaFast);
   bool strongADX = (g_adx >= InpADX_TrendMin);
   bool sepOk = (emaSepPts >= InpEMA_SepMinPts);
   if(strongADX && sepOk && (trendUp || trendDn))
   {
      why = StringFormat("ADX %.1f≥%.0f | EMA sep %.0f pts | viés %s",
                         g_adx, InpADX_TrendMin, emaSepPts, (trendUp ? "ALTA" : "BAIXA"));
      return true;
   }
   why = StringFormat("tendência fraca ADX=%.1f sep=%.0f", g_adx, emaSepPts);
   return false;
}

//+------------------------------------------------------------------+
bool PatternLateralStrong(string &why)
{
   if(!RefreshIndicators()) { why = "indicadores indisponíveis"; return false; }
   if(g_adx <= InpADX_LateralMax)
   {
      why = StringFormat("ADX %.1f≤%.0f lateral", g_adx, InpADX_LateralMax);
      return true;
   }
   why = StringFormat("não lateral ADX=%.1f", g_adx);
   return false;
}

//+------------------------------------------------------------------+
ENUM_MODULE InferLockedModule()
{
   if(g_pmActive) return MOD_MEANREV;
   if(CountOurPositions() <= 0) return MOD_NONE;
   // OB = sem TP; PB = com TP
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetDouble(POSITION_TP) <= 0.0)
         return MOD_OPENBREAK;
      return MOD_PULLBACK;
   }
   return MOD_NONE;
}

//+------------------------------------------------------------------+
// Cascata M5: A(OB) → B(PB) → C(PM). Lock até flat. OB aborta cedo → B/C antes das 11.
void ClassifyRegime(const datetime now)
{
   if(g_dayStopped || DailyLossHit())
   {
      g_regime = REG_RISCO_DIA;
      g_regimeWhy = StringFormat("STOP DIA: dayPnL R$%.0f <= -R$%.0f", DayPnLMoney(), DailyLossLimitMoney());
      g_activeMod = MOD_NONE;
      return;
   }

   if(ShouldFlatDay(now))
   {
      g_regime = REG_FORA;
      g_regimeWhy = "após flat 16:00";
      g_activeMod = MOD_NONE;
      g_lockedMod = MOD_NONE;
      return;
   }

   if(!g_boxReady)
   {
      g_regime = REG_UNKNOWN;
      g_activeMod = MOD_NONE;
      g_regimeWhy = "aguardando caixa 09:00-09:15";
      return;
   }

   UpdateOpenBreakAbort(now);

   // Lock: posição / pacote PM — não abre outra estratégia
   if(CountOurPositions() > 0 || g_pmActive)
   {
      if(g_lockedMod == MOD_NONE)
         g_lockedMod = InferLockedModule();
      g_activeMod = g_lockedMod;
      if(g_lockedMod == MOD_OPENBREAK)
      {
         g_regime = REG_R1_ABERTURA_OK;
         g_regimeWhy = "LOCK OpenBreak — gestão até flat";
      }
      else if(g_lockedMod == MOD_PULLBACK)
      {
         g_regime = REG_R3_TENDENCIA;
         g_regimeWhy = "LOCK Pullback — gestão até flat";
      }
      else if(g_lockedMod == MOD_MEANREV)
      {
         g_regime = REG_R4_LATERAL;
         g_regimeWhy = StringFormat("LOCK PreçoMédio %d/%d — pernas ok, sem outra estratégia",
                                    g_pmLegs, InpPM_MaxLegs);
      }
      else
      {
         g_regime = REG_FORA;
         g_regimeWhy = "posição nossa sem módulo identificado";
         g_activeMod = MOD_NONE;
      }
      return;
   }

   // Flat → libera lock e volta à cascata
   g_lockedMod = MOD_NONE;

   if(g_tradesToday >= InpMaxTradesDay)
   {
      g_regime = REG_FORA;
      g_regimeWhy = StringFormat("teto segurança %d trades", InpMaxTradesDay);
      g_activeMod = MOD_NONE;
      return;
   }

   // --- A: OpenBreak (só enquanto ainda há indício / janela) ---
   if(InpEnableOpenBreak && !g_obAborted && !g_r2Day && g_tradesOB == 0 && InMorningOBEntry(now))
   {
      g_regime = REG_R1_ABERTURA_OK;
      g_regimeWhy = StringFormat("cascata A | caixa OK %.0f pts — OpenBreak", g_boxPts);
      g_activeMod = MOD_OPENBREAK;
      return;
   }

   // --- B/C: só se OB liberou (ou desligado) e estamos na sessão de cascata ---
   if(!OpenBreakReleased())
   {
      // Ainda montando / esperando caixa válida sem estar na janela OB
      g_regime = (g_r2Day ? REG_R2_EXPLOSIVA : REG_R1_ABERTURA_OK);
      g_regimeWhy = "aguardando janela/aborto OpenBreak antes de B/C";
      g_activeMod = MOD_NONE;
      return;
   }

   if(!InCascadeSession(now))
   {
      g_regime = REG_FORA;
      g_regimeWhy = OpenBreakReleased()
         ? StringFormat("OB liberado (%s) — fora sessão B/C", g_obAbortWhy)
         : "fora sessão cascata";
      g_activeMod = MOD_NONE;
      return;
   }

   string why = "";

   // --- B: Pullback (tendência forte) ---
   if(InpEnablePullback && g_tradesPB == 0 && PatternTrendStrong(why))
   {
      g_regime = REG_R3_TENDENCIA;
      g_regimeWhy = StringFormat("cascata B | %s — Pullback%s", why,
                                 (g_obAborted ? " (OB liberou cedo)" : ""));
      g_activeMod = MOD_PULLBACK;
      return;
   }

   // --- C: Preço médio (lateral; não em dia R2 caótico) ---
   if(InpEnablePrecoMedio && g_tradesMR == 0 && !g_r2Day && PatternLateralStrong(why))
   {
      g_regime = REG_R4_LATERAL;
      g_regimeWhy = StringFormat("cascata C | %s — PreçoMédio%s", why,
                                 (g_obAborted ? " (OB liberou cedo)" : ""));
      g_activeMod = MOD_MEANREV;
      return;
   }

   if(g_r2Day)
   {
      g_regime = REG_R2_EXPLOSIVA;
      g_regimeWhy = StringFormat("R2 — PM bloqueado; sem fit Pullback | %s", why);
      g_activeMod = MOD_NONE;
      return;
   }

   g_regime = REG_FORA;
   g_regimeWhy = StringFormat("cascata sem fit | OB=%s | %s",
                              (g_obAborted ? g_obAbortWhy : "n/a"), why);
   g_activeMod = MOD_NONE;
}

//+------------------------------------------------------------------+
void LogRegimeChange()
{
   if(g_regime == g_regimeLogged) return;
   LogWhy(StringFormat("REGIME %s → %s | módulo=%s | %s",
                       RegimeName(g_regimeLogged), RegimeName(g_regime),
                       ModuleName(g_activeMod), g_regimeWhy));
   g_regimeLogged = g_regime;
}

//+------------------------------------------------------------------+
bool VolumeOkBreak(const int shift)
{
   if(!InpOB_UseVolume || hVol == INVALID_HANDLE) return true;
   double vol[];
   ArraySetAsSeries(vol, true);
   int need = 22;
   if(CopyBuffer(hVol, 0, shift, need, vol) < need) return false;
   double sum = 0.0;
   for(int i = 1; i <= 20; i++) sum += vol[i];
   double avg = sum / 20.0;
   if(avg <= 0.0) return false;
   return (vol[0] >= avg * InpOB_VolMinX);
}

//+------------------------------------------------------------------+
bool OpenMarket(const int dir, const double sl, const double tp, const string tag)
{
   double vol = CalcVolume();
   if(vol <= 0.0) { LogSkip("volume=0"); return false; }
   int spread = CurrentSpreadPoints();
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints)
   {
      LogSkip(StringFormat("spread %d > %d", spread, InpMaxSpreadPoints));
      return false;
   }
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return false;

   double sln = sl, tpn = tp;
   NormalizeSLTP(dir > 0, (dir > 0 ? ask : bid), sln, tpn);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   string cmt = StringFormat("%s|%s", InpTradeComment, tag);
   bool ok = (dir > 0) ? trade.Buy(vol, _Symbol, ask, sln, tpn, cmt)
                       : trade.Sell(vol, _Symbol, bid, sln, tpn, cmt);
   if(ok)
   {
      g_tradesToday++;
      g_beDone = false;
      LogWhy(StringFormat("ENTRADA %s %s vol=%.0f @≈%.0f SL=%.0f TP=%.0f | regime=%s | %s | spread=%d",
                          tag, (dir > 0 ? "BUY" : "SELL"), vol, (dir > 0 ? ask : bid),
                          sln, tpn, RegimeName(g_regime), g_regimeWhy, spread));
   }
   else
      PrintFormat("Router: ordem falhou ret=%u %s", trade.ResultRetcode(), trade.ResultComment());
   return ok;
}

//+------------------------------------------------------------------+
void ModuleOpenBreak()
{
   if(!InpEnableOpenBreak) return;
   if(g_activeMod != MOD_OPENBREAK) return;
   if(g_tradesOB > 0 || g_tradesToday >= InpMaxTradesDay) return;
   if(CountOurPositions() > 0) return;
   if(!g_boxReady || g_r2Day) return;

   datetime barTime = iTime(_Symbol, InpTF, 1);
   if(barTime == 0 || barTime == g_lastBarOB) return;
   g_lastBarOB = barTime; // 1 avaliação por barra (mesmo se skip)

   double close1 = iClose(_Symbol, InpTF, 1);
   if(close1 <= 0.0) return;
   double buf = InpOB_BreakBufferPts * (_Point > 0.0 ? _Point : 1.0);
   if(MathAbs(_Point - 1.0) < 1e-8) buf = (double)InpOB_BreakBufferPts;

   int dir = 0;
   if(close1 > g_boxHigh + buf) dir = 1;
   else if(close1 < g_boxLow - buf) dir = -1;
   else
   {
      LogSkip(StringFormat("OpenBreak aguarda rompimento | close=%.0f caixa %.0f–%.0f", close1, g_boxLow, g_boxHigh));
      return;
   }

   if(!VolumeOkBreak(1))
   {
      LogSkip("OpenBreak volume fraco no rompimento");
      return;
   }

   if(!InMorningOBEntry(barTime))
   {
      LogSkip("OpenBreak rompimento fora da janela");
      return;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = (dir > 0 ? ask : bid);
   double sl = (dir > 0) ? (g_boxLow - InpOB_BreakBufferPts) : (g_boxHigh + InpOB_BreakBufferPts);
   if(_Point > 0.0 && MathAbs(_Point - 1.0) > 1e-8)
      sl = (dir > 0) ? (g_boxLow - InpOB_BreakBufferPts * _Point)
                     : (g_boxHigh + InpOB_BreakBufferPts * _Point);
   sl = SnapPrice(sl);

   // Sem TP fixo — gestão BE+trail
   if(OpenMarket(dir, sl, 0.0, "OB"))
   {
      g_tradesOB++;
      g_lockedMod = MOD_OPENBREAK;
   }
}

//+------------------------------------------------------------------+
void ManageOpenBreakPosition()
{
   if(CountOurPositions() <= 0) return;
   if(g_pmActive) return; // pacote R4 não usa trail OB
   // Só trail posições sem TP (OpenBreak); Pullback tem TP
   if(!RefreshIndicators()) return;

   double trailStart = g_atrPts * InpOB_TrailStartATR;
   double trailDist  = g_atrPts * InpOB_TrailATR;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double tp = PositionGetDouble(POSITION_TP);
      if(tp > 0.0) continue; // Pullback/MR — não trail aqui

      long type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double newSL = sl;

      if(type == POSITION_TYPE_BUY)
      {
         double pp = (bid - open) / _Point;
         if(!g_beDone && pp >= InpOB_BE_Points)
         {
            newSL = SnapPrice(open + InpOB_BE_LockPts * _Point);
            g_beDone = true;
            LogWhy(StringFormat("OB BE armado BUY @ %.0f (lucro %.0f pts)", newSL, pp));
         }
         if(pp >= trailStart)
         {
            double tsl = SnapPrice(bid - trailDist * _Point);
            if(newSL <= 0.0 || tsl > newSL) newSL = tsl;
            if(sl > 0.0 && newSL < sl) newSL = sl;
         }
      }
      else
      {
         double pp = (open - ask) / _Point;
         if(!g_beDone && pp >= InpOB_BE_Points)
         {
            newSL = SnapPrice(open - InpOB_BE_LockPts * _Point);
            g_beDone = true;
            LogWhy(StringFormat("OB BE armado SELL @ %.0f (lucro %.0f pts)", newSL, pp));
         }
         if(pp >= trailStart)
         {
            double tsl = SnapPrice(ask + trailDist * _Point);
            if(newSL <= 0.0 || tsl < newSL) newSL = tsl;
            if(sl > 0.0 && newSL > sl) newSL = sl;
         }
      }

      if(newSL > 0.0 && MathAbs(newSL - sl) >= _Point)
      {
         if(trade.PositionModify(ticket, newSL, 0.0))
            LogWhy(StringFormat("OB trail/BE modify SL %.0f → %.0f", sl, newSL));
      }
   }
}

//+------------------------------------------------------------------+
void RefreshPullbackSignal()
{
   g_pbDir = 0;
   g_pbConsumed = false;
   if(!RefreshIndicators()) return;

   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   if(CopyRates(_Symbol, InpTF, 0, 3, bars) != 3) return;

   double f1[1], f2[1];
   if(CopyBuffer(hEMAFast, 0, 1, 1, f1) < 1) return;
   if(CopyBuffer(hEMAFast, 0, 2, 1, f2) < 1) return;

   MqlRates c = bars[1];
   g_pbSignalBar = c.time;
   g_pbHigh = c.high;
   g_pbLow = c.low;

   if(f1[0] > g_emaSlow && f1[0] > f2[0] &&
      c.low <= f1[0] && c.close > f1[0] && c.close > c.open)
   {
      g_pbDir = 1;
      LogWhy(StringFormat("Pullback SINAL BUY | bar %s hi=%.0f lo=%.0f | EMA20=%.0f EMA50=%.0f ADX=%.1f",
                          TimeToString(c.time, TIME_MINUTES), g_pbHigh, g_pbLow, f1[0], g_emaSlow, g_adx));
   }
   else if(f1[0] < g_emaSlow && f1[0] < f2[0] &&
           c.high >= f1[0] && c.close < f1[0] && c.close < c.open)
   {
      g_pbDir = -1;
      LogWhy(StringFormat("Pullback SINAL SELL | bar %s hi=%.0f lo=%.0f | EMA20=%.0f EMA50=%.0f ADX=%.1f",
                          TimeToString(c.time, TIME_MINUTES), g_pbHigh, g_pbLow, f1[0], g_emaSlow, g_adx));
   }
}

//+------------------------------------------------------------------+
void ModulePullback()
{
   if(!InpEnablePullback) return;
   if(g_activeMod != MOD_PULLBACK) return;
   if(g_tradesPB > 0) return;
   if(g_tradesToday >= InpMaxTradesDay) return;
   if(CountOurPositions() > 0) return;

   datetime currentBar = iTime(_Symbol, InpTF, 0);
   if(currentBar == 0) return;
   if(currentBar != g_lastBarAft)
   {
      g_lastBarAft = currentBar;
      RefreshPullbackSignal();
   }

   if(g_pbDir == 0 || g_pbConsumed) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double offset = (double)InpPB_EntryOffsetPts;
   if(_Point > 0.0 && MathAbs(_Point - 1.0) > 1e-8)
      offset = InpPB_EntryOffsetPts * _Point;

   bool trig = (g_pbDir > 0) ? (ask >= g_pbHigh + offset) : (bid <= g_pbLow - offset);
   if(!trig)
   {
      LogSkip(StringFormat("Pullback aguarda rompimento sinal | dir=%d hi=%.0f lo=%.0f", g_pbDir, g_pbHigh, g_pbLow));
      return;
   }

   g_pbConsumed = true;
   double price = (g_pbDir > 0 ? ask : bid);
   double sl = (g_pbDir > 0) ? (g_pbLow - InpPB_BufferPts) : (g_pbHigh + InpPB_BufferPts);
   if(_Point > 0.0 && MathAbs(_Point - 1.0) > 1e-8)
      sl = (g_pbDir > 0) ? (g_pbLow - InpPB_BufferPts * _Point)
                         : (g_pbHigh + InpPB_BufferPts * _Point);
   sl = SnapPrice(sl);
   double risk = MathAbs(price - sl);
   double riskPts = (_Point > 0.0 ? risk / _Point : risk);
   if(riskPts < InpPB_MinRiskPts || riskPts > InpPB_MaxRiskPts)
   {
      LogSkip(StringFormat("Pullback risco %.0f pts fora [%d–%d]", riskPts, InpPB_MinRiskPts, InpPB_MaxRiskPts));
      return;
   }
   double tp = (g_pbDir > 0) ? (price + InpPB_RewardRisk * risk) : (price - InpPB_RewardRisk * risk);
   tp = SnapPrice(tp);

   if(OpenMarket(g_pbDir, sl, tp, "PB"))
   {
      g_tradesPB++;
      g_lockedMod = MOD_PULLBACK;
   }
}

//+------------------------------------------------------------------+
bool OpenPM_Leg(const int dir, const double lots, const string tag)
{
   if(lots <= 0.0) { LogSkip("PM lote=0"); return false; }
   int spread = CurrentSpreadPoints();
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints)
   {
      LogSkip(StringFormat("PM spread %d > %d", spread, InpMaxSpreadPoints));
      return false;
   }
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return false;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   string cmt = StringFormat("%s|%s", InpTradeComment, tag);
   // Sem SL/TP na ordem — gestão por stop ciclo + alvo BB/médio
   bool ok = (dir > 0) ? trade.Buy(lots, _Symbol, ask, 0.0, 0.0, cmt)
                       : trade.Sell(lots, _Symbol, bid, 0.0, 0.0, cmt);
   if(ok)
   {
      double px = (dir > 0 ? ask : bid);
      double prevVol = g_pmLotPerLeg * g_pmLegs;
      double newVol = prevVol + lots;
      if(g_pmLegs <= 0)
         g_pmAvg = px;
      else
         g_pmAvg = (g_pmAvg * prevVol + px * lots) / MathMax(newVol, lots);
      g_pmLastPrice = px;
      g_pmLegs++;
      g_pmDir = dir;
      g_pmActive = true;
      g_pmLotPerLeg = lots;
      LogWhy(StringFormat(
         "PM PERNA %d/%d %s lots=%.0f @≈%.0f | médio=%.0f | espaço≈%.0f pts | stopCiclo=-R$%.0f | ADX=%.1f BB mid=%.0f",
         g_pmLegs, InpPM_MaxLegs, (dir > 0 ? "BUY" : "SELL"), lots, px, g_pmAvg,
         PM_SpacePts(), InpPM_CycleStopBRL, g_adx, g_bbMid));
   }
   else
      PrintFormat("Router: PM ordem falhou ret=%u %s", trade.ResultRetcode(), trade.ResultComment());
   return ok;
}

//+------------------------------------------------------------------+
void PM_CloseCycle(const string reason)
{
   if(CountOurPositions() > 0)
      CloseAllOurs(reason);
   LogWhy(StringFormat("PM CICLO ENCERRADO | motivo=%s | pernas=%d médio=%.0f dayPnL=R$%.2f",
                       reason, g_pmLegs, g_pmAvg, DayPnLMoney()));
   PM_Reset();
}

//+------------------------------------------------------------------+
void ManagePrecoMedio()
{
   if(!g_pmActive) return;
   if(CountOurPositions() <= 0)
   {
      // broker fechou / netting zerou
      LogWhy("PM posição sumiu — reset ciclo");
      PM_Reset();
      return;
   }

   PM_SyncFromPosition();
   if(!RefreshIndicators()) return;

   double pnl = FloatingPnLOurs();
   if(pnl <= -MathAbs(InpPM_CycleStopBRL))
   {
      LogWhy(StringFormat("PM STOP CICLO | floating=R$%.2f <= -R$%.0f", pnl, InpPM_CycleStopBRL));
      PM_CloseCycle("PM_STOP_CICLO");
      return;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pt = (_Point > 0.0 ? _Point : 1.0);
   double minGain = InpPM_MinGainPts * pt;

   // Alvo: BB mid, garantindo pelo menos médio+40 pts a favor
   double target = g_bbMid;
   if(g_pmDir > 0)
   {
      if(target < g_pmAvg + minGain) target = g_pmAvg + minGain;
      if(bid >= target)
      {
         LogWhy(StringFormat("PM ALVO | bid=%.0f target=%.0f médio=%.0f BB=%.0f pnl=R$%.2f",
                             bid, target, g_pmAvg, g_bbMid, pnl));
         PM_CloseCycle("PM_ALVO");
         return;
      }
   }
   else if(g_pmDir < 0)
   {
      if(target > g_pmAvg - minGain) target = g_pmAvg - minGain;
      if(ask <= target)
      {
         LogWhy(StringFormat("PM ALVO | ask=%.0f target=%.0f médio=%.0f BB=%.0f pnl=R$%.2f",
                             ask, target, g_pmAvg, g_bbMid, pnl));
         PM_CloseCycle("PM_ALVO");
         return;
      }
   }

   // Adiciona perna se preço andou contra o espaçamento (mesmo ciclo / lock)
   if(g_pmLegs >= InpPM_MaxLegs) return;
   if(g_lockedMod != MOD_MEANREV && g_activeMod != MOD_MEANREV) return;

   double space = PM_SpacePts() * pt;
   bool add = false;
   if(g_pmDir > 0 && ask <= g_pmLastPrice - space) add = true;
   if(g_pmDir < 0 && bid >= g_pmLastPrice + space) add = true;
   if(!add) return;

   OpenPM_Leg(g_pmDir, g_pmLotPerLeg, StringFormat("PM%d", g_pmLegs + 1));
}

//+------------------------------------------------------------------+
void ModuleMeanRev()
{
   if(!InpEnablePrecoMedio && !g_pmActive) return;
   if(g_activeMod != MOD_MEANREV && !g_pmActive) return;

   // Sempre gerencia pacote aberto
   if(g_pmActive)
   {
      ManagePrecoMedio();
      return;
   }

   if(g_tradesMR > 0) return;
   if(g_tradesToday >= InpMaxTradesDay) return;
   if(CountOurPositions() > 0) return;
   if(!RefreshIndicators()) return;

   datetime barTime = iTime(_Symbol, InpTF, 1);
   if(barTime == 0 || barTime == g_lastBarAft) return;
   g_lastBarAft = barTime;

   double bandPts = (_Point > 0.0 ? (g_bbUpper - g_bbLower) / _Point : (g_bbUpper - g_bbLower));
   if(bandPts < InpMR_MinBandPts)
   {
      LogSkip(StringFormat("PM banda estreita %.0f pts", bandPts));
      return;
   }

   double close1 = iClose(_Symbol, InpTF, 1);
   int dir = 0;
   if(close1 <= g_bbLower) dir = 1;
   else if(close1 >= g_bbUpper) dir = -1;
   else
   {
      LogSkip(StringFormat("PM dentro das bandas close=%.0f [%.0f–%.0f]", close1, g_bbLower, g_bbUpper));
      return;
   }

   double lots = R4LotsPerLeg();
   LogWhy(StringFormat("PM SETUP dir=%s close=%.0f BB=[%.0f|%.0f|%.0f] ADX=%.1f lots/perna=%.0f espaço=%.0fpts stopCiclo=R$%.0f",
                       (dir > 0 ? "BUY" : "SELL"), close1, g_bbLower, g_bbMid, g_bbUpper,
                       g_adx, lots, PM_SpacePts(), InpPM_CycleStopBRL));

   if(OpenPM_Leg(dir, lots, "PM1"))
   {
      g_lockedMod = MOD_MEANREV;
      if(!g_pmCycleCounted)
      {
         g_tradesMR++;
         g_tradesToday++;
         g_pmCycleCounted = true;
      }
   }
}

//+------------------------------------------------------------------+
void UpdateChartComment()
{
   double dayPnL = DayPnLMoney();
   double stopLim = DailyLossLimitMoney();
   string boxTag = (!g_boxReady ? "montando" : (g_r2Day ? "R2" : "OK"));
   string sinal = "-";
   if(g_activeMod == MOD_PULLBACK && g_pbDir != 0 && !g_pbConsumed)
      sinal = StringFormat("PB %s%.0f",
                           (g_pbDir > 0 ? "BUY>" : "SELL<"),
                           (g_pbDir > 0 ? g_pbHigh + InpPB_EntryOffsetPts : g_pbLow - InpPB_EntryOffsetPts));
   else if(g_activeMod == MOD_OPENBREAK)
      sinal = "OB wait break";
   else if(g_pmActive)
      sinal = StringFormat("PM %d/%d avg=%.0f f=R$%.0f", g_pmLegs, InpPM_MaxLegs, g_pmAvg, FloatingPnLOurs());
   else if(g_activeMod == MOD_MEANREV)
      sinal = "PM wait BB";

   string lockTag = (g_lockedMod != MOD_NONE)
      ? StringFormat("LOCK %s", ModuleAbbr(g_lockedMod))
      : (g_obAborted ? "OBabort" : "free");

   // Telinha enxuta (Comment já quebra com \n)
   string txt = StringFormat(
      "RR v1.05 %s | %s %s | %s\n"
      "%s\n"
      "flags OB%d PB%d PM%d | %s | cx=%.0f(%s)\n"
      "ADX%.0f EMA%.0f/%.0f ATR%.0f spr%d\n"
      "cap R$%.0f | dPnL R$%.0f | STOP -R$%.0f%s\n"
      "PM cicR$%.0f lot%.0f sp%.0f | t %d/%d [%d|%d|%d]\n"
      "act: %s\n"
      "skip: %s",
      _Symbol, RegimeAbbr(g_regime), ModuleAbbr(g_activeMod), sinal,
      ClipStr(g_regimeWhy, 64),
      (InpEnableOpenBreak ? 1 : 0), (InpEnablePullback ? 1 : 0), (InpEnablePrecoMedio ? 1 : 0),
      lockTag, g_boxPts, boxTag,
      g_adx, g_emaFast, g_emaSlow, g_atrPts, CurrentSpreadPoints(),
      GetCapital(), dayPnL, stopLim, (g_dayStopped ? " HALT" : ""),
      InpPM_CycleStopBRL, R4LotsPerLeg(), PM_SpacePts(),
      g_tradesToday, InpMaxTradesDay, g_tradesOB, g_tradesPB, g_tradesMR,
      ClipStr(g_lastAction, 72),
      ClipStr(g_lastSkip, 72)
   );
   Comment(txt);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(!IsWinSymbol())
      Print("Router: aviso — símbolo não parece WIN: ", _Symbol);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   EnsureSeedCapital();

   hEMAFast = iMA(_Symbol, InpTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMASlow = iMA(_Symbol, InpTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hADX = iADX(_Symbol, InpTF, InpADXPeriod);
   hATR = iATR(_Symbol, InpTF, InpATRPeriod);
   hVol = iVolumes(_Symbol, InpTF, VOLUME_TICK);
   hBB  = iBands(_Symbol, InpTF, InpMR_BBPeriod, 0, InpMR_BBDev, PRICE_CLOSE);

   if(hEMAFast == INVALID_HANDLE || hEMASlow == INVALID_HANDLE ||
      hADX == INVALID_HANDLE || hATR == INVALID_HANDLE || hBB == INVALID_HANDLE)
   {
      Print("Router: falha ao criar indicadores");
      return INIT_FAILED;
   }

   ResetDayIfNeeded();
   RefreshIndicators();

   Print("========== RegimeRouterWIN v1.05 ==========");
   Print("RR init | cascata OB>PB>PM | lock flat | sem meta | log curto (2 linhas/M5)");
   PrintFormat("RR init | flags OB=%d PB=%d PM=%d | maxT=%d | STOP=%.0f%% (~R$%.0f)",
               (InpEnableOpenBreak ? 1 : 0), (InpEnablePullback ? 1 : 0), (InpEnablePrecoMedio ? 1 : 0),
               InpMaxTradesDay, InpStopDiaPct, DailyLossLimitMoney());
   PrintFormat("RR init | seed=R$%.2f (chart=R$%.2f) | vol=%.0f | magic=%I64d",
               g_seedCapital, InpClearSaldo, CalcVolume(), InpMagic);
   PrintFormat("RR init | cx[%g-%g] OB<=%02d:%02d flatOB %02d:%02d | BC<=%02d:%02d | PB ADX>=%.0f PM<=%.0f",
               InpMinBoxPts, InpMaxBoxPts, InpOB_EntryEndH, InpOB_EntryEndM, InpOB_FlatH, InpOB_FlatM,
               InpAftEndH, InpAftEndM, InpADX_TrendMin, InpADX_LateralMax);
   Print("RR leyenda | R1..R4/STOP/FORA | OB/PB/PM | IDLE WAIT LOCK POS MAX STOP | t=OB|PB|PM");
   Print("==========================================");

   UpdateChartComment();
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
   if(hVol != INVALID_HANDLE) IndicatorRelease(hVol);
   if(hBB != INVALID_HANDLE) IndicatorRelease(hBB);
   PrintFormat("Router: deinit reason=%d", reason);
}

//+------------------------------------------------------------------+
void OnTick()
{
   ResetDayIfNeeded();
   datetime now = TimeTradeServer();
   BuildOrUpdateBox(now);
   RefreshIndicators();
   ClassifyRegime(now);
   LogRegimeChange();
   LogBarPulse(now); // a cada 5 min: regime + se opera/não + motivo
   UpdateChartComment();

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      return;

   // STOP DIA
   if(DailyLossHit() || g_dayStopped)
   {
      if(!g_dayStopped)
      {
         g_dayStopped = true;
         LogWhy(StringFormat("STOP DIA ATIVADO | dayPnL=R$%.2f limite=-R$%.2f → flat e bloqueio",
                             DayPnLMoney(), DailyLossLimitMoney()));
      }
      if(InpFlatOnDailyLoss && CountOurPositions() > 0)
         CloseAllOurs("STOP_DIA");
      if(g_pmActive) PM_Reset();
      g_regime = REG_RISCO_DIA;
      UpdateChartComment();
      return;
   }

   // Flat fim do dia
   if(ShouldFlatDay(now))
   {
      if(CountOurPositions() > 0)
         CloseAllOurs("FLAT_16h");
      if(g_pmActive) PM_Reset();
      return;
   }

   // Flat posições OpenBreak às 11:00 (mesmo se ainda gerenciando)
   if(ShouldFlatOBPosition(now) && CountOurPositions() > 0)
   {
      // Fecha só se for posição sem TP (OB). Com TP (PB/MR) após 11h mantém até flat 16h ou TP/SL
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetDouble(POSITION_TP) <= 0.0)
         {
            if(trade.PositionClose(ticket))
               LogWhy(StringFormat("OB flat 11:00 ticket=%I64u", ticket));
         }
      }
   }

   // Gestão OB
   ManageOpenBreakPosition();

   // R4 pacote ativo: gerencia mesmo se regime mudou
   if(g_pmActive)
      ManagePrecoMedio();

   // Módulos de entrada
   if(g_activeMod == MOD_OPENBREAK)
      ModuleOpenBreak();
   else if(g_activeMod == MOD_PULLBACK)
      ModulePullback();
   else if(g_activeMod == MOD_MEANREV && !g_pmActive)
      ModuleMeanRev();
}
//+------------------------------------------------------------------+
