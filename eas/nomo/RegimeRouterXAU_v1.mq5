//+------------------------------------------------------------------+
//| RegimeRouterXAU_v1.mq5                                            |
//| Nomo / XAUUSD — roteador de regimes (único EA ativo Nomo)                |
//| R1 caixa Londres OK → OpenBreak | R2 explosiva → fora ORB, tarde se R3|
//| R3 Tendência → Pullback | R4 Lateral → mean-reversion 1 ct       |
//| STOP DIA 5% único | logs ricos | telinha detalhada               |
//| v1.00: ouro M15 | sessão GMT | saldo seed US$254 | log a cada M15         |
//+------------------------------------------------------------------+
#property copyright "Vitor / mt5-eas"
#property version   "1.00"
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
input group "=== Volume / capital (Nomo) ==="
input double InpAccountUsd        = 254.0;   // Saldo Nomo atual (fallback)
input double InpFixedLots         = 0.01;    // minilote (conta ~US$254)
input double InpMaxLots           = 0.05;
input bool   InpIncludeFloating   = true;
input bool   InpResetVirtualSeed  = false;   // true uma vez se quiser resetar época/fallback
input bool   InpSaveDayHistory    = true;
input string InpHistoryFile       = "RegimeRouterXAU_v1_equity.csv";
input double InpMinCapTrade       = 200.0;   // Abaixo disso não opera

input group "=== Risco único do dia ==="
input double InpStopDiaPct        = 5.0;      // STOP DIA absoluto (todos os módulos)
input bool   InpFlatOnDailyLoss   = true;
input int    InpMaxTradesDay      = 2;        // Máx total (manhã+tarde)
input int    InpMaxSpreadPoints   = 600;     // Ouro Nomo: spread largo em pts

input group "=== Caixa abertura Londres GMT (R1/R2) ==="
input int    InpBoxStartH         = 13;      // 13:00 GMT ≈ 10:00 BRT
input int    InpBoxStartM         = 0;
input int    InpBoxEndH           = 13;
input int    InpBoxEndM           = 30;      // 30 min de caixa
input double InpMinBoxPts         = 150.0;   // ~US$1.5 se point=0.01
input double InpMaxBoxPts         = 2500.0;  // ~US$25 — acima = R2

input group "=== Módulo OpenBreak (R1 pós-caixa) ==="
input int    InpOB_EntryEndH      = 15;      // entrada OB até 15:00 GMT
input int    InpOB_EntryEndM      = 0;
input int    InpOB_FlatH          = 16;      // flat posições OB
input int    InpOB_FlatM          = 0;
input int    InpOB_BreakBufferPts = 50;
input bool   InpOB_UseVolume      = true;
input double InpOB_VolMinX        = 1.00;
input int    InpOB_BE_Points      = 300;     // ~US$3 se point=0.01
input int    InpOB_BE_LockPts     = 50;
input double InpOB_TrailStartATR  = 0.80;
input double InpOB_TrailATR       = 0.50;

input group "=== Sessão tarde GMT (R3/R4) ==="
input int    InpAftStartH         = 16;
input int    InpAftStartM         = 5;
input int    InpAftEndH           = 19;      // overlap ouro
input int    InpAftEndM           = 0;
input int    InpFlatH             = 21;      // 21:00 GMT ≈ 18:00 BRT
input int    InpFlatM             = 0;
input bool   InpWeekdaysOnly      = true;

input group "=== Classificação R3 / R4 ==="
input int    InpEMAFast           = 20;
input int    InpEMASlow           = 50;
input int    InpADXPeriod         = 14;
input double InpADX_TrendMin      = 20.0;     // R3
input double InpADX_LateralMax    = 18.0;     // R4
input double InpEMA_SepMinPts     = 400.0;    // ~US$4 sep mínima p/ R3
input int    InpATRPeriod         = 14;

input group "=== Módulo Pullback (R3) ==="
input double InpPB_RewardRisk     = 2.0;
input int    InpPB_BufferPts      = 80;
input int    InpPB_EntryOffsetPts = 30;
input int    InpPB_MinRiskPts     = 150;
input int    InpPB_MaxRiskPts     = 5000;

input group "=== Módulo Mean-Reversion (R4) ==="
input int    InpMR_BBPeriod       = 20;
input double InpMR_BBDev          = 2.0;
input int    InpMR_TargetBufferPts = 50;
input int    InpMR_SL_BufferPts   = 120;
input int    InpMR_MinBandPts     = 200;

input group "=== Geral ==="
input ENUM_TIMEFRAMES InpTF       = PERIOD_M15;
input long   InpMagic             = 320932;   // Único — EA ativo Nomo XAU
input int    InpSlippagePoints    = 80;
input string InpTradeComment      = "RegimeRouterXAU";
input bool   InpVerboseLog        = true;

//------------------------ Estado ------------------------------------
datetime g_dayStart = 0;
double   g_dayStartEquity = 0.0;
datetime g_lastBarOB = 0;
datetime g_lastBarAft = 0;
datetime g_lastStatusBar = 0; // pulse de log a cada M15
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
string   g_capitalSource = "broker";

// Caixa
double   g_boxHigh = 0.0;
double   g_boxLow  = 0.0;
double   g_boxPts  = 0.0;
bool     g_boxReady = false;
bool     g_boxLogged = false;
bool     g_r2Day = false;          // abertura explosiva/inválida

// Regime / UI
ENUM_REGIME g_regime = REG_UNKNOWN;
ENUM_REGIME g_regimeLogged = REG_UNKNOWN;
ENUM_MODULE g_activeMod = MOD_NONE;
string   g_regimeWhy = "";
string   g_lastAction = "";
string   g_lastSkip = "";
datetime g_lastSkipLog = 0;

// OpenBreak gestão
bool     g_beDone = false;

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
string ModuleName(const ENUM_MODULE m)
{
   switch(m)
   {
      case MOD_OPENBREAK: return "OpenBreak";
      case MOD_PULLBACK:  return "Pullback";
      case MOD_MEANREV:   return "MeanRev";
      default:            return "nenhum";
   }
}

//+------------------------------------------------------------------+
void LogWhy(const string msg)
{
   g_lastAction = msg;
   if(InpVerboseLog)
      PrintFormat("Router: %s", msg);
}

//+------------------------------------------------------------------+
void LogSkip(const string msg)
{
   g_lastSkip = msg;
   // Sempre registra (barra M15 limita a frequência via módulos / pulse)
   if(InpVerboseLog)
      PrintFormat("Router: SKIP | %s", msg);
}

//+------------------------------------------------------------------+
// Log a cada nova barra M15
void LogBarPulse(const datetime now)
{
   datetime bar0 = iTime(_Symbol, InpTF, 0);
   if(bar0 == 0 || bar0 == g_lastStatusBar)
      return;
   g_lastStatusBar = bar0;

   if(!InpVerboseLog)
      return;

   string decision = "";
   if(g_dayStopped || g_regime == REG_RISCO_DIA)
      decision = "NÃO OPERA — STOP DIA";
   else if(g_activeMod == MOD_NONE)
      decision = "NÃO OPERA — sem módulo neste regime/janela";
   else if(CountOurPositions() > 0)
      decision = "EM POSIÇÃO — gestão ativa (sem nova entrada)";
   else if(g_tradesToday >= InpMaxTradesDay)
      decision = "NÃO OPERA — max trades do dia";
   else
      decision = StringFormat("AGUARDANDO SINAL — módulo %s", ModuleName(g_activeMod));

   string last = (g_lastSkip != "" ? g_lastSkip : g_lastAction);
   PrintFormat(
      "Router: M15 %s | REGIME=%s | módulo=%s | %s | %s | caixa=%.0fpts%s | ADX=%.1f EMA%.0f/%.0f | dayPnL=US$%.2f | trades=%d/%d (OB=%d PB=%d MR=%d) | detalhe: %s",
      TimeToString(bar0, TIME_MINUTES),
      RegimeName(g_regime),
      ModuleName(g_activeMod),
      decision,
      g_regimeWhy,
      g_boxPts,
      (g_r2Day ? " R2" : (g_boxReady ? " OK" : " …")),
      g_adx, g_emaFast, g_emaSlow,
      DayPnLMoney(),
      g_tradesToday, InpMaxTradesDay, g_tradesOB, g_tradesPB, g_tradesMR,
      last
   );
}

//+------------------------------------------------------------------+
double ClampVolume(const double v)
{
   double vol = MathMax(0.0, v);
   vol = MathMin(vol, InpMaxLots);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 0.01;
   if(vmin <= 0.0) vmin = 0.01;
   vol = MathFloor(vol / step + 1e-8) * step;
   if(vol < vmin) vol = 0.0;
   if(vol > vmax && vmax > 0.0) vol = vmax;
   return NormalizeDouble(vol, 2);
}

//+------------------------------------------------------------------+
double CalcVolume() { return ClampVolume(InpFixedLots); }

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
bool IsXauSymbol()
{
   string s = _Symbol;
   StringToUpper(s);
   return (StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0);
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
string GVPrefix() { return StringFormat("RegimeRouterXAU_v100_%I64d_", InpMagic); }

//+------------------------------------------------------------------+
void EnsureSeedCapital()
{
   string keySeed = GVPrefix() + "seed";
   string keyEpoch = GVPrefix() + "epoch";
   if(InpResetVirtualSeed || !GlobalVariableCheck(keySeed) || !GlobalVariableCheck(keyEpoch))
   {
      g_seedCapital = InpAccountUsd;
      g_equityEpoch = TimeTradeServer();
      GlobalVariableSet(keySeed, g_seedCapital);
      GlobalVariableSet(keyEpoch, (double)g_equityEpoch);
      LogWhy(StringFormat("semente/fallback US$%.2f época %s", g_seedCapital,
                          TimeToString(g_equityEpoch, TIME_DATE|TIME_MINUTES)));
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

      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         pnlOut += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP) + comm;
         commissionSum += comm;
      }
   }
   feesOut = 0.0;
}

//+------------------------------------------------------------------+
double GetCapital()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double broker = MathMax(eq, bal);
   if(broker >= 50.0)
   {
      g_capitalSource = "broker";
      if(InpIncludeFloating)
         return MathMax(0.0, eq); // equity já inclui floating
      return MathMax(0.0, bal);
   }
   // Fallback se Nomo zerar leitura
   g_capitalSource = "fallback";
   double cap = InpAccountUsd;
   if(InpIncludeFloating) cap += FloatingPnLOurs();
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
   g_regimeWhy = "aguardando caixa 09:00-09:15";
   g_lastAction = "novo dia";
   g_lastSkip = "";
   g_beDone = false;
   g_pbDir = 0;
   g_pbConsumed = false;
   g_lastBarOB = 0;
   g_lastBarAft = 0;
   g_lastStatusBar = 0;

   LogWhy(StringFormat("NOVO DIA | capital start US$%.2f | STOP DIA %.1f%% = US$%.2f | lots=%.2f magic=%I64d",
                       g_dayStartEquity, InpStopDiaPct, DailyLossLimitMoney(), CalcVolume(), InpMagic));
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
      return;
   }

   if(!g_boxReady)
   {
      g_regime = REG_UNKNOWN;
      g_activeMod = MOD_NONE;
      return;
   }

   // Manhã
   if(MinutesOfDay(now) < HM(InpAftStartH, InpAftStartM))
   {
      if(g_r2Day)
      {
         g_regime = REG_R2_EXPLOSIVA;
         g_regimeWhy = StringFormat("caixa %.0f pts fora do range — manhã FORA; tarde só se R3", g_boxPts);
         g_activeMod = MOD_NONE;
      }
      else if(InMorningOBEntry(now) && g_tradesOB == 0)
      {
         g_regime = REG_R1_ABERTURA_OK;
         g_regimeWhy = StringFormat("caixa OK %.0f pts — módulo OpenBreak ativo", g_boxPts);
         g_activeMod = MOD_OPENBREAK;
      }
      else
      {
         g_regime = (g_r2Day ? REG_R2_EXPLOSIVA : REG_R1_ABERTURA_OK);
         g_regimeWhy = (g_tradesOB > 0)
            ? "OpenBreak já operou — aguardando tarde/gestão"
            : "fora da janela de entrada OpenBreak (após 10:30)";
         g_activeMod = MOD_NONE;
      }
      return;
   }

   // Tarde: classifica R3 / R4
   if(!InAfternoon(now))
   {
      g_regime = REG_FORA;
      g_regimeWhy = "fora da sessão tarde";
      g_activeMod = MOD_NONE;
      return;
   }

   if(!RefreshIndicators())
   {
      g_regime = REG_FORA;
      g_regimeWhy = "indicadores indisponíveis";
      g_activeMod = MOD_NONE;
      return;
   }

   double emaSep = MathAbs(g_emaFast - g_emaSlow);
   double emaSepPts = (_Point > 0.0 ? emaSep / _Point : emaSep);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool trendUp = (g_emaFast > g_emaSlow && bid > g_emaFast);
   bool trendDn = (g_emaFast < g_emaSlow && bid < g_emaFast);
   bool strongADX = (g_adx >= InpADX_TrendMin);
   bool sepOk = (emaSepPts >= InpEMA_SepMinPts);

   if(strongADX && sepOk && (trendUp || trendDn))
   {
      g_regime = REG_R3_TENDENCIA;
      g_regimeWhy = StringFormat("ADX %.1f≥%.0f | EMA sep %.0f pts | viés %s — Pullback",
                                 g_adx, InpADX_TrendMin, emaSepPts, (trendUp ? "ALTA" : "BAIXA"));
      // R2: tarde só se R3 — já estamos em R3, ok. R1 também ok.
      if(g_tradesPB == 0 && g_tradesMR == 0 && g_tradesToday < InpMaxTradesDay)
         g_activeMod = MOD_PULLBACK;
      else
         g_activeMod = MOD_NONE;
      return;
   }

   if(g_adx <= InpADX_LateralMax)
   {
      // R2 explosiva: lateral à tarde = FORA (não mean-rev em dia caótico sem tendência)
      // Na verdade alinhamos: R4 mean-rev quando lateral. Em R2 day, se for lateral (não R3), fora.
      if(g_r2Day)
      {
         g_regime = REG_R2_EXPLOSIVA;
         g_regimeWhy = StringFormat("R2+lateral (ADX %.1f) — SEM mean-rev; só entraria se virasse R3", g_adx);
         g_activeMod = MOD_NONE;
         return;
      }

      g_regime = REG_R4_LATERAL;
      g_regimeWhy = StringFormat("ADX %.1f≤%.0f — MeanRev 1ct (medir)", g_adx, InpADX_LateralMax);
      if(g_tradesPB == 0 && g_tradesMR == 0 && g_tradesToday < InpMaxTradesDay)
         g_activeMod = MOD_MEANREV;
      else
         g_activeMod = MOD_NONE;
      return;
   }

   // Zona cinza entre ADX 18 e 20 ou sem alinhamento
   g_regime = REG_FORA;
   g_regimeWhy = StringFormat("zona cinza ADX=%.1f sep=%.0f — sem módulo (aguarda R3/R4 claro)", g_adx, emaSepPts);
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
      LogWhy(StringFormat("ENTRADA %s %s lots=%.2f @≈%.2f SL=%.2f TP=%.2f | regime=%s | %s | spread=%d",
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
      g_tradesOB++;
}

//+------------------------------------------------------------------+
void ManageOpenBreakPosition()
{
   if(CountOurPositions() <= 0) return;
   // Só trail posições sem TP (OpenBreak); Pullback/MR têm TP
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
   if(g_activeMod != MOD_PULLBACK) return;
   if(g_tradesPB > 0 || g_tradesMR > 0) return;
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
      g_tradesPB++;
}

//+------------------------------------------------------------------+
void ModuleMeanRev()
{
   if(g_activeMod != MOD_MEANREV) return;
   if(g_tradesMR > 0 || g_tradesPB > 0) return;
   if(g_tradesToday >= InpMaxTradesDay) return;
   if(CountOurPositions() > 0) return;
   if(!RefreshIndicators()) return;

   datetime barTime = iTime(_Symbol, InpTF, 1);
   if(barTime == 0 || barTime == g_lastBarAft) return;
   g_lastBarAft = barTime;

   double bandPts = (_Point > 0.0 ? (g_bbUpper - g_bbLower) / _Point : (g_bbUpper - g_bbLower));
   if(bandPts < InpMR_MinBandPts)
   {
      LogSkip(StringFormat("MeanRev banda estreita %.0f pts", bandPts));
      return;
   }

   double close1 = iClose(_Symbol, InpTF, 1);
   int dir = 0;
   // Fecha fora/na banda → mean reversion
   if(close1 <= g_bbLower) dir = 1;       // oversold → compra
   else if(close1 >= g_bbUpper) dir = -1; // overbought → venda
   else
   {
      LogSkip(StringFormat("MeanRev dentro das bandas close=%.0f [%.0f–%.0f]", close1, g_bbLower, g_bbUpper));
      return;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (dir > 0 ? ask : bid);
   double sl, tp;
   if(dir > 0)
   {
      sl = SnapPrice(g_bbLower - InpMR_SL_BufferPts * (_Point > 0 ? _Point : 1.0));
      if(MathAbs(_Point - 1.0) < 1e-8) sl = SnapPrice(g_bbLower - InpMR_SL_BufferPts);
      tp = SnapPrice(g_bbMid - InpMR_TargetBufferPts);
      if(MathAbs(_Point - 1.0) < 1e-8) tp = SnapPrice(g_bbMid - InpMR_TargetBufferPts);
   }
   else
   {
      sl = SnapPrice(g_bbUpper + InpMR_SL_BufferPts);
      if(_Point > 0.0 && MathAbs(_Point - 1.0) > 1e-8)
         sl = SnapPrice(g_bbUpper + InpMR_SL_BufferPts * _Point);
      tp = SnapPrice(g_bbMid + InpMR_TargetBufferPts);
      if(_Point > 0.0 && MathAbs(_Point - 1.0) > 1e-8)
         tp = SnapPrice(g_bbMid + InpMR_TargetBufferPts * _Point);
   }

   LogWhy(StringFormat("MeanRev setup dir=%d close=%.0f BB=[%.0f %.0f %.0f] ADX=%.1f",
                       dir, close1, g_bbLower, g_bbMid, g_bbUpper, g_adx));

   if(OpenMarket(dir, sl, tp, "MR"))
      g_tradesMR++;
}

//+------------------------------------------------------------------+
void UpdateChartComment()
{
   double dayPnL = DayPnLMoney();
   double stopLim = DailyLossLimitMoney();
   string boxLine = g_boxReady
      ? StringFormat("caixa %.0f–%.0f (%.0f pts) %s", g_boxLow, g_boxHigh, g_boxPts,
                     (g_r2Day ? "INVÁLIDA→R2" : "OK→R1"))
      : "caixa: montando / aguardando 09:15";

   string sinal = "—";
   if(g_activeMod == MOD_PULLBACK && g_pbDir != 0 && !g_pbConsumed)
      sinal = StringFormat("PB %s wait %s%.0f", (g_pbDir > 0 ? "BUY" : "SELL"),
                           (g_pbDir > 0 ? ">" : "<"),
                           (g_pbDir > 0 ? g_pbHigh + InpPB_EntryOffsetPts : g_pbLow - InpPB_EntryOffsetPts));
   else if(g_activeMod == MOD_OPENBREAK)
      sinal = "OB aguarda rompimento caixa";
   else if(g_activeMod == MOD_MEANREV)
      sinal = "MR aguarda fechamento na banda";

   string txt = StringFormat(
      "RegimeRouterXAU v1.00 | %s\n"
      "REGIME: %s\n"
      "porque: %s\n"
      "módulo: %s | %s\n"
      "%s\n"
      "ADX %.1f | EMA%d %.0f / EMA%d %.0f | ATR≈%.0f pts | spread %d\n"
      "BB %.0f | %.0f | %.0f\n"
      "capital US$%.0f (%s) | dayPnL US$%.2f | STOP -US$%.2f (%.1f%%)%s\n"
      "trades %d/%d (OB=%d PB=%d MR=%d) | lots=%.2f | magic %I64d\n"
      "última ação: %s\n"
      "último skip: %s",
      _Symbol,
      RegimeName(g_regime),
      g_regimeWhy,
      ModuleName(g_activeMod), sinal,
      boxLine,
      g_adx, InpEMAFast, g_emaFast, InpEMASlow, g_emaSlow, g_atrPts, CurrentSpreadPoints(),
      g_bbLower, g_bbMid, g_bbUpper,
      GetCapital(), g_capitalSource, dayPnL, stopLim, InpStopDiaPct,
      (g_dayStopped ? " | PARADO" : ""),
      g_tradesToday, InpMaxTradesDay, g_tradesOB, g_tradesPB, g_tradesMR, CalcVolume(), InpMagic,
      g_lastAction,
      g_lastSkip
   );
   Comment(txt);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(!IsXauSymbol())
      Print("Router: aviso — símbolo não parece XAU/GOLD: ", _Symbol);

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

   Print("========== RegimeRouterXAU v1.00 ==========");
   Print("Router: log a cada barra M15 (Router: M15 …) + SKIP/ENTRADA com motivo");
   PrintFormat("capital=US$%.2f fallback=US$%.2f lots=%.2f magic=%I64d STOP DIA=%.1f%% (~US$%.2f)",
               GetCapital(), InpAccountUsd, CalcVolume(), InpMagic, InpStopDiaPct, DailyLossLimitMoney());
   PrintFormat("R1 caixa [%g–%g] pts | OB entry até %02d:%02d flat %02d:%02d",
               InpMinBoxPts, InpMaxBoxPts, InpOB_EntryEndH, InpOB_EntryEndM, InpOB_FlatH, InpOB_FlatM);
   PrintFormat("Tarde %02d:%02d–%02d:%02d | R3 ADX>=%.0f sepEMA>=%.0f | R4 ADX<=%.0f MeanRev BB",
               InpAftStartH, InpAftStartM, InpAftEndH, InpAftEndM,
               InpADX_TrendMin, InpEMA_SepMinPts, InpADX_LateralMax);
   Print("EAs Nomo arquivados em eas/nomo/archive/ — use SÓ este no gráfico XAUUSD M15.");
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
   if(InpWeekdaysOnly)
   {
      MqlDateTime wdt; TimeToStruct(now, wdt);
      if(wdt.day_of_week == 0 || wdt.day_of_week == 6)
      {
         g_regime = REG_FORA;
         g_regimeWhy = "fim de semana — ouro fechado / sem sessão";
         g_activeMod = MOD_NONE;
         UpdateChartComment();
         return;
      }
   }
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
         LogWhy(StringFormat("STOP DIA ATIVADO | dayPnL=US$%.2f limite=-US$%.2f → flat e bloqueio",
                             DayPnLMoney(), DailyLossLimitMoney()));
      }
      if(InpFlatOnDailyLoss && CountOurPositions() > 0)
         CloseAllOurs("STOP_DIA");
      g_regime = REG_RISCO_DIA;
      UpdateChartComment();
      return;
   }

   // Flat fim do dia
   if(ShouldFlatDay(now))
   {
      if(CountOurPositions() > 0)
         CloseAllOurs("FLAT_16h");
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

   if(GetCapital() < InpMinCapTrade)
   {
      LogSkip(StringFormat("capital US$%.2f < min US$%.2f", GetCapital(), InpMinCapTrade));
      UpdateChartComment();
      return;
   }

   // Módulos de entrada
   if(g_activeMod == MOD_OPENBREAK)
      ModuleOpenBreak();
   else if(g_activeMod == MOD_PULLBACK)
      ModulePullback();
   else if(g_activeMod == MOD_MEANREV)
      ModuleMeanRev();
}
//+------------------------------------------------------------------+
