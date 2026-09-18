//+------------------------------------------------------------------+
//| ScalpWIN_v2.mq5                                                   |
//| Daytrade WIN (Clear) - rompimento + escada de lucro % + soft lock |
//| Volume por capital | SL até 5% do capital | stop dia 10%          |
//| Sem teto de trades/dia | parciais: 2%→50% · 5%→+25% · resto trail |
//| v2.07: SL/preço alinhados ao tick do WIN (fix invalid stops 10016) |
//+------------------------------------------------------------------+
#property copyright "Vitor / mt5-eas"
#property version   "2.07"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_WIN_SIZING
{
   SIZING_BY_CAPITAL = 0,  // Faixas por capital virtual
   SIZING_FIXED      = 1
};

enum ENUM_CAPITAL_MODE
{
   CAPITAL_VIRTUAL = 0,  // Semente + PnL do magic (recomendado Clear)
   CAPITAL_MANUAL  = 1,  // Valor fixo (não soma PnL)
   CAPITAL_BROKER  = 2,  // Equity/balance/free do MT5
   CAPITAL_AUTO    = 3   // Broker se confiável; senão virtual
};

//------------------------ Inputs ------------------------------------
input group "=== Volume / capital virtual ==="
input ENUM_WIN_SIZING   InpSizingMode        = SIZING_BY_CAPITAL;
input ENUM_CAPITAL_MODE InpCapitalMode       = CAPITAL_VIRTUAL; // Clear: Virtual
input double InpSeedBal           = 850.0;   // Saldo Clear atual (R$850)
input double InpBandStart          = 500.0;   // 500-1500→1 | 1500-2500→2 | ...
input double InpBandWidth          = 1000.0;
input double InpFixedVolume        = 1.0;
input double InpMaxVolume          = 10.0;
input double InpMinCapitalTrade    = 500.0;
input double InpBrokerMinReliable  = 50.0;
input bool   InpIncludeFloating    = true;
input bool   InpEstimateFees       = true;    // Desconta taxas B3/corretagem estimadas
input double InpFeePerSide         = 0.25;    // ~R$0,25 por contrato por lado (ida ou volta)
input bool   InpResetVirtualSeed   = false;   // true só se quiser recomeçar a semente
input bool   InpSaveDayHistory     = true;
input string InpHistoryFile        = "ScalpWIN_v2_equity.csv";

input group "=== Risco diário ==="
input double InpDailyLossPercent   = 10.0;    // Para o dia se prejuízo >= X% do capital do dia
input bool   InpFlatOnDailyLoss    = true;
input int    InpMaxPositions       = 1;
input int    InpMaxSpreadPoints    = 40;

input group "=== Sessão (horário do servidor MT5) ==="
input int    InpSessStartH         = 10;
input int    InpSessStartM         = 30;      // 10:30 (um pouco antes que 10:45)
input int    InpSessEndH           = 15;
input int    InpSessEndM           = 45;      // 15:45
input int    InpFlatH              = 16;      // Flat 16:00
input int    InpFlatM              = 0;

input group "=== Entrada (rompimento) ==="
input int    InpBreakN            = 3;       // 3 barras (mais entradas)
input int    InpEMAFast            = 50;
input int    InpEMASlow            = 200;
input bool   InpUseEmaTrend        = true;
input int    InpADXPeriod          = 14;
input double InpAdxGate           = 18.0;    // Afrouxado p/ mercado lateral (era 22)
input bool   InpUseADXFilter       = true;
input double InpBodyMin           = 0.25;    // Corpo mínimo mais baixo (era 0.40)
input bool   InpUseVolumeFilter    = true;    // Só entra com volume acima da média
input int    InpVolAvgBars         = 20;      // Média de tick volume
input double InpVolGate           = 0.85;    // Aceita volume um pouco abaixo da média
input ENUM_TIMEFRAMES InpTF        = PERIOD_M5;

input group "=== Stop (folgado, teto em % do capital) ==="
input double InpSL_ATR_Mult        = 1.50;    // SL inicial = ATR * mult
input int    InpATRPeriod          = 14;
input double InpMaxSL_CapitalPct   = 5.0;     // Teto: SL não passa de X% do capital
input int    InpMinSL_Points       = 120;
input int    InpMaxSL_Points       = 800;     // Segurança absoluta em pontos

input group "=== Escada de lucro (% do capital do dia) ==="
input double InpLadder1_Pct        = 2.0;     // 1º alvo: realiza esta % do capital
input double InpLadder1_CloseFrac  = 0.50;    // Fecha 50% do volume original
input double InpLadder2_Pct        = 5.0;     // 2º alvo
input double InpLadder2_CloseFrac  = 0.25;    // Fecha +25% do volume original
input double InpLadder3_Pct        = 8.0;     // 3º alvo (opcional)
input double InpLadder3_CloseFrac  = 0.25;    // Fecha o restante (~25%)
input bool   InpUseLadder3         = false;   // Se false, o resto só soft lock

input group "=== Soft lock (runner) ==="
input double InpSoftStart_ATR      = 0.80;    // Arma trail após X ATR de lucro
input double InpSoftLock_ATR       = 0.30;
input double InpTrail_ATR          = 0.50;
input double InpSoftTightenAfter1  = 0.85;    // Após 1ª parcial, trail *= este fator (mais apertado)
input double InpSoftTightenAfter2  = 0.70;

input group "=== Geral ==="
input long   InpMagic              = 260917;
input int    InpSlippagePoints     = 30;
input string InpTradeComment       = "ScalpWIN_v2";
input bool   InpVerboseLog         = true;

//------------------------ Estado ------------------------------------
datetime g_dayStart = 0;
double   g_dayStartEquity = 0.0;
datetime g_lastBarTime = 0;
bool     g_dayStopped = false;
bool     g_loggedDailyFlat = false;
string   g_capitalSource = "n/a";
string   g_lastSkipReason = "";

// Estado da posição atual (escada)
ulong    g_posTicket = 0;
double   g_posOpenVol = 0.0;
double   g_posOpenPrice = 0.0;
int      g_ladderStep = 0;       // 0=nada, 1=fez 1º, 2=fez 2º, 3=fez 3º
double   g_realizedThisTrade = 0.0;
datetime g_lastCloseFailLog = 0;
double   g_seedCapital = 0.0;     // semente efetiva (GV ou input)
double   g_realizedAll = 0.0;     // PnL realizado desde a época da semente
double   g_feesAll = 0.0;         // taxas estimadas desde a época
datetime g_equityEpoch = 0;       // só conta deals a partir daqui (evita double-count)

int hEMA50 = INVALID_HANDLE;
int hEMA200 = INVALID_HANDLE;
int hADX = INVALID_HANDLE;
int hATR = INVALID_HANDLE;
int hVol = INVALID_HANDLE;

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
   int need = MathMax(stops, freeze);
   if(need < 1) need = 1;
   return need;
}

//+------------------------------------------------------------------+
void LogAccountSnapshot()
{
   PrintFormat("ScalpWIN2: conta MT5 | balance=R$%.2f equity=R$%.2f free=R$%.2f margin=R$%.2f",
               AccountInfoDouble(ACCOUNT_BALANCE),
               AccountInfoDouble(ACCOUNT_EQUITY),
               AccountInfoDouble(ACCOUNT_MARGIN_FREE),
               AccountInfoDouble(ACCOUNT_MARGIN));
}

//+------------------------------------------------------------------+
double BrokerReportedCapital()
{
   return MathMax(AccountInfoDouble(ACCOUNT_EQUITY),
          MathMax(AccountInfoDouble(ACCOUNT_BALANCE),
                  AccountInfoDouble(ACCOUNT_MARGIN_FREE)));
}

//+------------------------------------------------------------------+
string GVPrefix()
{
   // v205: nova chave → aplica semente R$850 sem precisar Reset manual
   return StringFormat("ScalpWIN2_v205_%I64d_", InpMagic);
}

//+------------------------------------------------------------------+
string GVNameSeed()
{
   return GVPrefix() + "seed";
}

//+------------------------------------------------------------------+
string GVNameEpoch()
{
   return GVPrefix() + "epoch";
}

//+------------------------------------------------------------------+
string GVNameLastDay()
{
   return GVPrefix() + "lastday";
}

//+------------------------------------------------------------------+
string GVNameLastDayStart()
{
   return GVPrefix() + "daystart";
}

//+------------------------------------------------------------------+
void EnsureSeedCapital()
{
   string keySeed = GVNameSeed();
   string keyEpoch = GVNameEpoch();

   if(InpResetVirtualSeed || !GlobalVariableCheck(keySeed) || !GlobalVariableCheck(keyEpoch))
   {
      g_seedCapital = InpSeedBal;
      g_equityEpoch = TimeTradeServer();
      GlobalVariableSet(keySeed, g_seedCapital);
      GlobalVariableSet(keyEpoch, (double)g_equityEpoch);
      PrintFormat("ScalpWIN2: semente R$%.2f a partir de %s (taxas≈R$%.2f/lado) | GV %s",
                  g_seedCapital, TimeToString(g_equityEpoch, TIME_DATE|TIME_MINUTES),
                  InpFeePerSide, keySeed);
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
// PnL + taxas só DEPOIS da época da semente (saldo Clear já reflete o passado)
void CalcRealizedAndFeesSinceEpoch(double &pnlOut, double &feesOut)
{
   pnlOut = 0.0;
   feesOut = 0.0;
   EnsureSeedCapital();
   datetime from = g_equityEpoch;
   if(from <= 0) from = 0;

   if(!HistorySelect(from, TimeTradeServer() + 1))
      return;

   double commissionSum = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;

      datetime t = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(t < from) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      double vol = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double comm = HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      // Taxa estimada em cada lado (abertura/fechamento)
      if(InpEstimateFees && InpFeePerSide > 0.0 &&
         (entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_OUT ||
          entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY))
      {
         feesOut += InpFeePerSide * MathMax(vol, 1.0);
      }

      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         pnlOut += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP)
                 + comm;
         commissionSum += comm;
      }
   }

   // Se o MT5 já trouxe comissão real relevante, não desconta estimativa de novo
   if(InpEstimateFees && MathAbs(commissionSum) >= 0.01)
      feesOut = 0.0;
}

//+------------------------------------------------------------------+
double RealizedPnLAllTime()
{
   double pnl, fees;
   CalcRealizedAndFeesSinceEpoch(pnl, fees);
   g_realizedAll = pnl;
   g_feesAll = fees;
   return pnl;
}

//+------------------------------------------------------------------+
// Capital virtual = semente Clear + PnL novo - taxas (+ floating)
double GetVirtualCapital()
{
   EnsureSeedCapital();
   double pnl, fees;
   CalcRealizedAndFeesSinceEpoch(pnl, fees);
   g_realizedAll = pnl;
   g_feesAll = fees;

   double cap = g_seedCapital + pnl - fees;
   if(InpIncludeFloating)
      cap += FloatingPnLOurs();
   g_capitalSource = "virtual";
   return MathMax(0.0, cap);
}

//+------------------------------------------------------------------+
double GetCapital()
{
   if(InpCapitalMode == CAPITAL_VIRTUAL)
      return GetVirtualCapital();

   if(InpCapitalMode == CAPITAL_MANUAL)
   {
      g_capitalSource = "manual";
      return MathMax(0.0, InpSeedBal);
   }

   double broker = BrokerReportedCapital();
   if(InpCapitalMode == CAPITAL_BROKER)
   {
      g_capitalSource = "broker";
      return MathMax(0.0, broker);
   }

   // AUTO
   if(broker >= InpBrokerMinReliable)
   {
      g_capitalSource = "broker";
      return broker;
   }
   return GetVirtualCapital();
}

//+------------------------------------------------------------------+
// Faixas: 500-1500→1 | 1500-2500→2 | 2500-3500→3 | ...
double ContractsFromCapitalBands(const double capital)
{
   if(capital < InpMinCapitalTrade || capital < InpBandStart)
      return 0.0;

   double width = InpBandWidth;
   if(width <= 0.0) width = 1000.0;

   double raw = MathFloor((capital - InpBandStart) / width + 1e-8) + 1.0;
   if(raw < 1.0) raw = 1.0;
   return ClampVolume(raw);
}

//+------------------------------------------------------------------+
void LogSkip(const string reason)
{
   g_lastSkipReason = reason;
   if(InpVerboseLog)
      PrintFormat("ScalpWIN2: SKIP | %s", reason);
}

//+------------------------------------------------------------------+
double DailyLossLimitMoney()
{
   double base = (g_dayStartEquity > 0.0 ? g_dayStartEquity : GetCapital());
   return base * MathAbs(InpDailyLossPercent) / 100.0;
}

//+------------------------------------------------------------------+
double CalcVolume()
{
   if(InpSizingMode == SIZING_FIXED)
      return ClampVolume(InpFixedVolume);

   double capital = GetCapital();
   double raw = ContractsFromCapitalBands(capital);
   if(raw <= 0.0)
      return 0.0;

   // Se a Clear reportar margem livre útil, respeita o teto de margem
   double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(free > InpBrokerMinReliable)
   {
      double marginOne = 0.0;
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(price <= 0.0) price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(price > 0.0 && OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, price, marginOne) && marginOne > 0.0)
      {
         double byMargin = MathFloor(free / marginOne + 1e-8);
         if(byMargin < raw) raw = byMargin;
      }
   }
   return ClampVolume(raw);
}

//+------------------------------------------------------------------+
void AppendDayHistory(const datetime dayStamp, const double dayStartCap, const double dayPnL, const double dayEndCap, const double vol)
{
   if(!InpSaveDayHistory)
      return;

   string path = InpHistoryFile;
   bool exists = FileIsExist(path, FILE_COMMON);
   // Tenta pasta comum; se falhar, Files local do terminal
   int h = FileOpen(path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h == INVALID_HANDLE)
      h = FileOpen(path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      PrintFormat("ScalpWIN2: não gravou histórico (%s) err=%d", path, GetLastError());
      return;
   }

   FileSeek(h, 0, SEEK_END);
   if(FileTell(h) == 0)
      FileWriteString(h, "date,day_start,day_pnl,day_end,contracts,seed,realized_all,fees_est,source\n");

   MqlDateTime dt;
   TimeToStruct(dayStamp, dt);
   string line = StringFormat("%04d-%02d-%02d,%.2f,%.2f,%.2f,%.0f,%.2f,%.2f,%.2f,%s\n",
                              dt.year, dt.mon, dt.day,
                              dayStartCap, dayPnL, dayEndCap, vol,
                              g_seedCapital, g_realizedAll, g_feesAll, g_capitalSource);
   FileWriteString(h, line);
   FileClose(h);
   PrintFormat("ScalpWIN2: histórico + %s | ini=R$%.2f pnl=R$%.2f fees=R$%.2f fim=R$%.2f vol≈%.0f",
               StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day),
               dayStartCap, dayPnL, g_feesAll, dayEndCap, vol);
}

//+------------------------------------------------------------------+
void ResetDayIfNeeded()
{
   datetime now = TimeTradeServer();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   datetime day0 = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
   if(day0 != g_dayStart)
   {
      // Fecha o dia anterior no CSV (se havia um dia carregado)
      if(g_dayStart > 0)
      {
         double endCap = GetCapital();
         double dayPnL = DayPnLMoney();
         AppendDayHistory(g_dayStart, g_dayStartEquity, dayPnL, endCap, CalcVolume());
         GlobalVariableSet(GVNameLastDay(), (double)g_dayStart);
         GlobalVariableSet(GVNameLastDayStart(), g_dayStartEquity);
      }

      g_dayStart = day0;
      g_dayStartEquity = GetCapital();
      g_dayStopped = false;
      g_loggedDailyFlat = false;
      g_lastSkipReason = "";
      PrintFormat("ScalpWIN2: novo dia | capital=R$%.2f (%s) seed=R$%.2f realized=R$%.2f | vol≈%.0f | faixa %.0f+%.0fn | stopDia=R$%.2f",
                  g_dayStartEquity, g_capitalSource, g_seedCapital, g_realizedAll,
                  CalcVolume(), InpBandStart, InpBandWidth, DailyLossLimitMoney());
   }
}

//+------------------------------------------------------------------+
bool IsWinSymbol()
{
   string s = _Symbol;
   StringToUpper(s);
   return (StringFind(s, "WIN") >= 0);
}

//+------------------------------------------------------------------+
bool SessionOpen(const datetime now)
{
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int nowMin = dt.hour * 60 + dt.min;
   return (nowMin >= InpSessStartH * 60 + InpSessStartM &&
           nowMin <  InpSessEndH * 60 + InpSessEndM);
}

//+------------------------------------------------------------------+
bool ShouldFlat(const datetime now)
{
   MqlDateTime dt;
   TimeToStruct(now, dt);
   return ((dt.hour * 60 + dt.min) >= InpFlatH * 60 + InpFlatM);
}

//+------------------------------------------------------------------+
void ResetPosState()
{
   g_posTicket = 0;
   g_posOpenVol = 0.0;
   g_posOpenPrice = 0.0;
   g_ladderStep = 0;
   g_realizedThisTrade = 0.0;
}

//+------------------------------------------------------------------+
double DayPnLMoney()
{
   datetime from = g_dayStart;
   datetime to = TimeTradeServer() + 1;
   if(!HistorySelect(from, to))
      return 0.0;

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
bool DailyLossHit()
{
   double limit = DailyLossLimitMoney();
   if(limit <= 0.0) return false;
   return (DayPnLMoney() <= -limit);
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
bool SelectOurPosition(ulong &ticket, long &type, double &vol, double &open, double &sl, double &profit)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      type = PositionGetInteger(POSITION_TYPE);
      vol = PositionGetDouble(POSITION_VOLUME);
      open = PositionGetDouble(POSITION_PRICE_OPEN);
      sl = PositionGetDouble(POSITION_SL);
      profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool Copy1(const int handle, const int buffer, double &out)
{
   double a[];
   if(CopyBuffer(handle, buffer, 1, 1, a) != 1)
      return false;
   out = a[0];
   return true;
}

//+------------------------------------------------------------------+
double ATRPrice()
{
   double atr = 0.0;
   if(!Copy1(hATR, 0, atr) || atr <= 0.0)
      return InpMinSL_Points * _Point;
   return atr;
}

//+------------------------------------------------------------------+
double ATRPointsRaw()
{
   double pt = _Point;
   if(pt <= 0.0) pt = 1.0;
   return ATRPrice() / pt;
}

//+------------------------------------------------------------------+
// R$ por 1 ponto de índice, para 1 contrato
double MoneyPerPointPerContract()
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || _Point <= 0.0)
      return 0.20; // fallback mini WIN
   return (tickValue / tickSize) * _Point;
}

//+------------------------------------------------------------------+
double TickSize()
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0) ts = _Point;
   if(ts <= 0.0) ts = 5.0; // WIN mini
   return ts;
}

//+------------------------------------------------------------------+
// mode > 0 = arredonda pra cima (SL de SELL); < 0 = pra baixo (SL de BUY); 0 = nearest
double SnapToTick(const double price, const int mode = 0)
{
   double ts = TickSize();
   if(ts <= 0.0) return price;
   double n = price / ts;
   if(mode > 0) n = MathCeil(n - 1e-8);
   else if(mode < 0) n = MathFloor(n + 1e-8);
   else n = MathRound(n);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(n * ts, digits);
}

//+------------------------------------------------------------------+
double ClampSLPoints(const double pts)
{
   double out = pts;
   if(out < InpMinSL_Points) out = InpMinSL_Points;
   if(out > InpMaxSL_Points) out = InpMaxSL_Points;
   // Alinha distância ao tick (WIN = 5 pts)
   double ts = TickSize();
   double pt = (_Point > 0.0 ? _Point : 1.0);
   double tickPts = ts / pt;
   if(tickPts > 1.0)
      out = MathCeil(out / tickPts) * tickPts;
   return out;
}

//+------------------------------------------------------------------+
// SL em pontos: ATR, limitado ao teto de X% do capital (folgado, não apertado)
double CalcSLPoints(const double volume)
{
   double atrPts = ATRPointsRaw();
   double slPts = ClampSLPoints(atrPts * InpSL_ATR_Mult);

   double cap = (g_dayStartEquity > 0.0 ? g_dayStartEquity : GetCapital());
   double maxMoney = cap * MathAbs(InpMaxSL_CapitalPct) / 100.0;
   double mpp = MoneyPerPointPerContract();
   if(mpp > 0.0 && volume > 0.0 && maxMoney > 0.0)
   {
      double maxPts = maxMoney / (mpp * volume);
      if(maxPts > 0.0 && slPts > maxPts)
         slPts = maxPts;
   }
   return ClampSLPoints(slPts);
}

//+------------------------------------------------------------------+
bool NormalizeSL(const long type, const double price, double &sl)
{
   if(sl <= 0.0 || price <= 0.0 || _Point <= 0.0)
      return false;

   double ts = TickSize();
   // Distância mínima: stops/freeze level, pelo menos 1 tick
   double minDist = MathMax(MinStopDistancePoints() * _Point, ts);
   // Folga extra de 1 tick — Clear/exchange às vezes rejeita no limite
   minDist += ts;

   bool isBuy = (type == POSITION_TYPE_BUY || type == ORDER_TYPE_BUY);
   if(isBuy)
   {
      if(price - sl < minDist)
         sl = price - minDist;
      sl = SnapToTick(sl, -1); // para baixo, longe do preço
      if(price - sl < minDist)
         sl = SnapToTick(price - minDist, -1);
   }
   else
   {
      if(sl - price < minDist)
         sl = price + minDist;
      sl = SnapToTick(sl, +1); // para cima, longe do preço
      if(sl - price < minDist)
         sl = SnapToTick(price + minDist, +1);
   }
   return (sl > 0.0);
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool VolumeOK(string &why)
{
   why = "";
   if(!InpUseVolumeFilter)
      return true;

   int need = MathMax(InpVolAvgBars + 2, 5);
   long vols[];
   ArraySetAsSeries(vols, true);
   if(CopyTickVolume(_Symbol, InpTF, 1, need, vols) < need)
   {
      why = "volume sem dados";
      return false;
   }

   long v1 = vols[0];
   double sum = 0.0;
   for(int i = 1; i <= InpVolAvgBars; i++)
      sum += (double)vols[i];
   double avg = sum / InpVolAvgBars;
   if(avg <= 0.0)
   {
      why = "média volume zerada";
      return false;
   }

   double mult = (double)v1 / avg;
   if(mult < InpVolGate)
   {
      why = StringFormat("volume fraco %.2fx < %.2fx (v=%I64d avg=%.0f)",
                         mult, InpVolGate, v1, avg);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool GetSignal(int &dir)
{
   dir = 0;
   double ema50, ema200, adx, atr;
   if(!Copy1(hEMA50, 0, ema50)) { LogSkip("EMA50 sem dados"); return false; }
   if(!Copy1(hEMA200, 0, ema200)) { LogSkip("EMA200 sem dados"); return false; }
   if(!Copy1(hADX, 0, adx)) { LogSkip("ADX sem dados"); return false; }
   if(!Copy1(hATR, 0, atr) || atr <= 0.0) { LogSkip("ATR sem dados"); return false; }

   if(InpUseADXFilter && adx < InpAdxGate)
   {
      LogSkip(StringFormat("ADX fraco %.1f < %.1f", adx, InpAdxGate));
      return true;
   }

   string volWhy = "";
   if(!VolumeOK(volWhy))
   {
      LogSkip(volWhy);
      return true;
   }

   double open1 = iOpen(_Symbol, InpTF, 1);
   double close1 = iClose(_Symbol, InpTF, 1);
   if(open1 <= 0.0 || close1 <= 0.0) { LogSkip("candle 1 sem OHLC"); return false; }

   double body = MathAbs(close1 - open1);
   double minBody = atr * InpBodyMin;
   if(body < minBody)
   {
      LogSkip(StringFormat("corpo fraco %.0f < %.0f pts", body / _Point, minBody / _Point));
      return true;
   }

   int bars = MathMax(2, InpBreakN);
   double hh = iHigh(_Symbol, InpTF, 2);
   double ll = iLow(_Symbol, InpTF, 2);
   for(int i = 3; i <= bars; i++)
   {
      hh = MathMax(hh, iHigh(_Symbol, InpTF, i));
      ll = MathMin(ll, iLow(_Symbol, InpTF, i));
   }

   bool bull = (close1 > open1);
   bool bear = (close1 < open1);
   bool upTrend = (ema50 > ema200);
   bool downTrend = (ema50 < ema200);

   if(bull && close1 > hh)
   {
      if(InpUseEmaTrend && !upTrend)
      {
         LogSkip("rompimento alta mas EMA contra");
         return true;
      }
      dir = 1;
      g_lastSkipReason = "";
      if(InpVerboseLog)
         PrintFormat("ScalpWIN2: SINAL BUY | close=%.0f > hh=%.0f | ADX=%.1f | bodyOK | volOK",
                     close1, hh, adx);
      return true;
   }

   if(bear && close1 < ll)
   {
      if(InpUseEmaTrend && !downTrend)
      {
         LogSkip("rompimento baixa mas EMA contra");
         return true;
      }
      dir = -1;
      g_lastSkipReason = "";
      if(InpVerboseLog)
         PrintFormat("ScalpWIN2: SINAL SELL | close=%.0f < ll=%.0f | ADX=%.1f | bodyOK | volOK",
                     close1, ll, adx);
      return true;
   }

   LogSkip(StringFormat("sem rompimento close=%.0f hh=%.0f ll=%.0f ADX=%.1f", close1, hh, ll, adx));
   return true;
}

//+------------------------------------------------------------------+
bool OpenTrade(const int dir)
{
   double vol = CalcVolume();
   if(vol <= 0.0)
   {
      LogSkip(StringFormat("sem volume (capital=R$%.2f %s)", GetCapital(), g_capitalSource));
      return false;
   }

   int spread = CurrentSpreadPoints();
   if(InpMaxSpreadPoints > 0 && spread > InpMaxSpreadPoints)
   {
      LogSkip(StringFormat("spread %d > %d", spread, InpMaxSpreadPoints));
      return false;
   }

   double slDist = CalcSLPoints(vol);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
   {
      Print("ScalpWIN2: sem cotação");
      return false;
   }

   // Validação de stops no exchange usa o lado oposto da cotação
   double sl = 0.0;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool ok = false;
   if(dir > 0)
   {
      double entry = SnapToTick(ask, 0);
      sl = entry - slDist * _Point;
      // BUY: SL abaixo do bid atual
      NormalizeSL(ORDER_TYPE_BUY, bid, sl);
      if(bid - sl < TickSize())
      {
         PrintFormat("ScalpWIN2: SL BUY inválido bid=%.0f sl=%.0f", bid, sl);
         return false;
      }
      ok = trade.Buy(vol, _Symbol, entry, sl, 0.0, InpTradeComment);
   }
   else
   {
      double entry = SnapToTick(bid, 0);
      sl = entry + slDist * _Point;
      // SELL: SL acima do ask atual (Clear valida contra ask)
      NormalizeSL(ORDER_TYPE_SELL, ask, sl);
      if(sl - ask < TickSize())
      {
         PrintFormat("ScalpWIN2: SL SELL inválido ask=%.0f sl=%.0f", ask, sl);
         return false;
      }
      ok = trade.Sell(vol, _Symbol, entry, sl, 0.0, InpTradeComment);
   }

   if(ok)
   {
      ResetPosState();
      g_posOpenVol = vol;
      g_posOpenPrice = (dir > 0 ? ask : bid);
      double slMoney = slDist * MoneyPerPointPerContract() * vol;
      PrintFormat("ScalpWIN2: %s vol=%.0f entry/SL tickOK SL=%.0f SL_pts=%.0f (~R$%.0f) spread=%d",
                  (dir > 0 ? "BUY" : "SELL"), vol, sl, slDist, slMoney, spread);
   }
   else
      PrintFormat("ScalpWIN2: falha ordem retcode=%u %s | ask=%.0f bid=%.0f sl=%.0f tick=%.0f",
                  trade.ResultRetcode(), trade.ResultComment(), ask, bid, sl, TickSize());

   return ok;
}

//+------------------------------------------------------------------+
double RoundDownVolume(const double v)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0.0) step = 1.0;
   double out = MathFloor(v / step + 1e-8) * step;
   if(out < vmin) out = 0.0;
   return out;
}

//+------------------------------------------------------------------+
bool CloseVolume(const ulong ticket, const double volClose, const string reason)
{
   if(volClose <= 0.0) return false;
   if(!PositionSelectByTicket(ticket))
      return false;

   double posVol = PositionGetDouble(POSITION_VOLUME);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double want = RoundDownVolume(volClose);
   if(want < vmin) return false;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   // Volume cheio: SEMPRE PositionClose (Clear rejeita ClosePartial do total → ret 10016)
   if(want >= posVol - 1e-8)
   {
      if(!trade.PositionClose(ticket))
      {
         datetime now = TimeTradeServer();
         if(now != g_lastCloseFailLog)
         {
            g_lastCloseFailLog = now;
            PrintFormat("ScalpWIN2: CLOSE total falhou %s vol=%.2f ret=%u %s",
                        reason, posVol, trade.ResultRetcode(), trade.ResultComment());
         }
         return false;
      }
      PrintFormat("ScalpWIN2: ZEROU %s | vol=%.2f | step=%d", reason, posVol, g_ladderStep);
      return true;
   }

   if(!trade.PositionClosePartial(ticket, want))
   {
      datetime now = TimeTradeServer();
      if(now != g_lastCloseFailLog)
      {
         g_lastCloseFailLog = now;
         PrintFormat("ScalpWIN2: parcial falhou %s vol=%.2f ret=%u %s — tentando close total",
                     reason, want, trade.ResultRetcode(), trade.ResultComment());
      }
      if(!trade.PositionClose(ticket))
         return false;
      PrintFormat("ScalpWIN2: ZEROU (fallback) %s | vol=%.2f", reason, posVol);
      return true;
   }
   PrintFormat("ScalpWIN2: PARCIAL %s | fechou %.2f de %.2f | step=%d", reason, want, posVol, g_ladderStep);
   return true;
}

//+------------------------------------------------------------------+
// Lucro da operação atual em R$ = floating + já realizado nesta trade (parciais)
double TradeProfitMoney(const double floating)
{
   return floating + g_realizedThisTrade;
}

//+------------------------------------------------------------------+
void SyncPosStateFromMarket()
{
   ulong ticket; long type; double vol, open, sl, profit;
   if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
   {
      if(g_posTicket != 0 || g_posOpenVol > 0.0)
         ResetPosState();
      return;
   }

   if(g_posTicket == 0 || g_posTicket != ticket)
   {
      // Nova posição (ou EA reiniciado com posição aberta)
      g_posTicket = ticket;
      if(g_posOpenVol <= 0.0)
         g_posOpenVol = vol;
      g_posOpenPrice = open;
      // Não zera ladder se já tínhamos step — mas em restart assume step 0
   }
}

//+------------------------------------------------------------------+
void ManageLadderAndSoftLock()
{
   SyncPosStateFromMarket();

   ulong ticket; long type; double vol, open, sl, profit;
   if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
      return;

   g_posTicket = ticket;
   if(g_posOpenVol <= 0.0)
      g_posOpenVol = vol;

   double cap = (g_dayStartEquity > 0.0 ? g_dayStartEquity : GetCapital());
   if(cap <= 0.0) return;

   double tradePnL = TradeProfitMoney(profit);
   double tradePct = 100.0 * tradePnL / cap;

   if(InpVerboseLog && tradePct >= InpLadder1_Pct && g_ladderStep < 1)
      PrintFormat("ScalpWIN2: alvo L1 em vista | tradePnL=R$%.2f (%.2f%% cap) vol=%.0f",
                  tradePnL, tradePct, vol);

   // --- Escada de realização ---
   if(g_ladderStep < 1 && tradePct >= InpLadder1_Pct)
   {
      double want = RoundDownVolume(g_posOpenVol * InpLadder1_CloseFrac);
      // 1 contrato (ou fracao < 2): zera tudo no 1º alvo
      if(g_posOpenVol < 2.0 - 1e-8 || vol < 2.0 - 1e-8)
         want = vol;
      want = MathMin(want, vol);
      if(want >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN) - 1e-8)
      {
         double before = profit;
         if(CloseVolume(ticket, want, StringFormat("L1 %.1f%% cap (pnl R$%.0f)", InpLadder1_Pct, tradePnL)))
         {
            g_ladderStep = 1;
            if(vol > 0.0)
               g_realizedThisTrade += before * (want / vol);
            if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
            {
               ResetPosState();
               return; // zerou tudo
            }
         }
      }
      else if(InpVerboseLog)
         Print("ScalpWIN2: L1 atingido mas volume insuficiente para parcial");
   }

   if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
      return;

   tradePnL = TradeProfitMoney(profit);
   tradePct = 100.0 * tradePnL / cap;

   if(g_ladderStep == 1 && tradePct >= InpLadder2_Pct)
   {
      double want = RoundDownVolume(g_posOpenVol * InpLadder2_CloseFrac);
      if(want <= 0.0 && vol > 0.0)
         want = RoundDownVolume(vol * 0.5);
      want = MathMin(want, vol);
      double remain = vol - want;
      double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(remain > 0.0 && remain < vmin)
         want = vol;

      if(want >= vmin - 1e-8)
      {
         double before = profit;
         if(CloseVolume(ticket, want, StringFormat("L2 %.1f%% cap (pnl R$%.0f)", InpLadder2_Pct, tradePnL)))
         {
            g_ladderStep = 2;
            if(vol > 0.0)
               g_realizedThisTrade += before * (want / vol);
            if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
            {
               ResetPosState();
               return;
            }
         }
      }
   }

   if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
      return;

   tradePnL = TradeProfitMoney(profit);
   tradePct = 100.0 * tradePnL / cap;

   if(InpUseLadder3 && g_ladderStep == 2 && tradePct >= InpLadder3_Pct)
   {
      if(CloseVolume(ticket, vol, StringFormat("L3 %.1f%% cap", InpLadder3_Pct)))
      {
         g_ladderStep = 3;
         ResetPosState();
         return;
      }
   }

   if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
      return;

   // Segurança: se já passou bem do L2 e ainda está 100% aberto (falha anterior), zera
   if(g_ladderStep < 1 && tradePct >= InpLadder2_Pct)
   {
      PrintFormat("ScalpWIN2: SAFETY close | trade %.1f%% >= L2 e escada ainda L0", tradePct);
      if(CloseVolume(ticket, vol, "SAFETY L2"))
      {
         ResetPosState();
         return;
      }
   }

   if(!SelectOurPosition(ticket, type, vol, open, sl, profit))
      return;

   tradePnL = TradeProfitMoney(profit);
   tradePct = 100.0 * tradePnL / cap;

   // --- Soft lock no runner (mais apertado após parciais) ---
   double atrPts = ATRPointsRaw();
   double startPts = atrPts * InpSoftStart_ATR;
   double lockPts  = atrPts * InpSoftLock_ATR;
   double trailPts = atrPts * InpTrail_ATR;
   if(g_ladderStep >= 2)
   {
      trailPts *= InpSoftTightenAfter2;
      lockPts  *= InpSoftTightenAfter2;
      startPts *= InpSoftTightenAfter2;
   }
   else if(g_ladderStep >= 1)
   {
      trailPts *= InpSoftTightenAfter1;
      lockPts  *= InpSoftTightenAfter1;
      startPts *= InpSoftTightenAfter1;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double newSL = sl;

   if(type == POSITION_TYPE_BUY)
   {
      double profitPts = (bid - open) / _Point;
      if(profitPts >= startPts)
      {
         double lockSL = open + lockPts * _Point;
         double trailSL = bid - trailPts * _Point;
         newSL = MathMax(lockSL, trailSL);
         if(sl > 0.0) newSL = MathMax(newSL, sl);
         // Após L1, não deixa SL abaixo do breakeven
         if(g_ladderStep >= 1)
            newSL = MathMax(newSL, open + MinStopDistancePoints() * _Point);
         NormalizeSL(POSITION_TYPE_BUY, bid, newSL);
      }
   }
   else
   {
      double profitPts = (open - ask) / _Point;
      if(profitPts >= startPts)
      {
         double lockSL = open - lockPts * _Point;
         double trailSL = ask + trailPts * _Point;
         newSL = MathMin(lockSL, trailSL);
         if(sl > 0.0) newSL = MathMin(newSL, sl);
         if(g_ladderStep >= 1)
            newSL = MathMin(newSL, open - MinStopDistancePoints() * _Point);
         NormalizeSL(POSITION_TYPE_SELL, ask, newSL);
      }
   }

   if(newSL > 0.0 && MathAbs(newSL - sl) >= _Point)
   {
      trade.SetExpertMagicNumber(InpMagic);
      trade.SetDeviationInPoints(InpSlippagePoints);
      trade.SetTypeFillingBySymbol(_Symbol);
      if(!trade.PositionModify(ticket, newSL, 0.0))
         PrintFormat("ScalpWIN2: softlock falhou ret=%u %s | newSL=%.0f bid=%.0f ask=%.0f",
                     trade.ResultRetcode(), trade.ResultComment(), newSL, bid, ask);
      else if(InpVerboseLog)
         PrintFormat("ScalpWIN2: SOFT+ SL %.0f -> %.0f | ladder=%d | tradePnL=R$%.0f (%.1f%%)",
                     sl, newSL, g_ladderStep, tradePnL, tradePct);
   }
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
      if(!trade.PositionClose(ticket) && InpVerboseLog)
         PrintFormat("ScalpWIN2: close falhou ticket=%I64u ret=%u (%s)",
                     ticket, trade.ResultRetcode(), reason);
   }
   ResetPosState();
}

//+------------------------------------------------------------------+
void UpdateChartComment()
{
   string status = g_dayStopped ? "STOP DIA 10% (sem entradas)"
                  : (SessionOpen(TimeTradeServer()) ? "SESSÃO" : "FORA");
   string ladder = StringFormat("L%d", g_ladderStep);
   string skip = (g_lastSkipReason != "" ? "\nskip: " + g_lastSkipReason : "");
   string txt = StringFormat(
      "ScalpWIN v2.06 | %s\ncap R$%.0f (%s) seed R$%.0f | fees R$%.2f | vol≈%.0f\ndayPnL R$%.0f | spread %d | escada %s | %s%s",
      _Symbol,
      GetCapital(),
      g_capitalSource,
      g_seedCapital,
      g_feesAll,
      CalcVolume(),
      DayPnLMoney(),
      CurrentSpreadPoints(),
      ladder,
      status,
      skip
   );
   Comment(txt);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(!IsWinSymbol())
      Print("ScalpWIN2: aviso - símbolo não parece WIN: ", _Symbol);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   hEMA50  = iMA(_Symbol, InpTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200 = iMA(_Symbol, InpTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hADX    = iADX(_Symbol, InpTF, InpADXPeriod);
   hATR    = iATR(_Symbol, InpTF, InpATRPeriod);
   hVol    = iVolumes(_Symbol, InpTF, VOLUME_TICK);

   if(hEMA50 == INVALID_HANDLE || hEMA200 == INVALID_HANDLE ||
      hADX == INVALID_HANDLE || hATR == INVALID_HANDLE ||
      (InpUseVolumeFilter && hVol == INVALID_HANDLE))
   {
      Print("ScalpWIN2: falha indicadores");
      return INIT_FAILED;
   }

   LogAccountSnapshot();
   EnsureSeedCapital();
   ResetDayIfNeeded();
   SyncPosStateFromMarket();

   if(DailyLossHit())
   {
      g_dayStopped = true;
      PrintFormat("ScalpWIN2: STOP DIA já ativo | dayPnL=R$%.2f | limite=R$%.2f",
                  DayPnLMoney(), DailyLossLimitMoney());
   }

   PrintFormat("ScalpWIN_v2.06 init | %s | capital=R$%.2f (%s) seed=R$%.2f realized=R$%.2f fees=R$%.2f | vol≈%.0f | magic=%I64d",
               _Symbol, GetCapital(), g_capitalSource, g_seedCapital, g_realizedAll, g_feesAll,
               CalcVolume(), InpMagic);
   if(MathAbs(g_seedCapital - 850.0) > 0.5)
      PrintFormat("ScalpWIN2: AVISO seed=R$%.0f (esperado R$850). Remova o EA do gráfico e arraste de novo sem .set antigo.", g_seedCapital);
   PrintFormat("faixas: R$%.0f+k*R$%.0f | taxa≈R$%.2f/lado (%s) | hist=%s | epoch=%s",
               InpBandStart, InpBandWidth, InpFeePerSide,
               (InpEstimateFees ? "on" : "off"),
               (InpSaveDayHistory ? InpHistoryFile : "off"),
               TimeToString(g_equityEpoch, TIME_DATE|TIME_MINUTES));
   PrintFormat("sessao %02d:%02d-%02d:%02d flat %02d:%02d | break=%d ADX>=%.1f body>=%.2fxATR | volFiltro=%s (x%.2f/%d)",
               InpSessStartH, InpSessStartM, InpSessEndH, InpSessEndM,
               InpFlatH, InpFlatM, InpBreakN, InpAdxGate, InpBodyMin,
               (InpUseVolumeFilter ? "sim" : "nao"), InpVolGate, InpVolAvgBars);
   PrintFormat("escada: %.1f%%→fecha %.0f%% | %.1f%%→fecha +%.0f%% | L3=%s | SL ATR=%.2fx teto %.1f%% cap | stopDia=%.1f%%",
               InpLadder1_Pct, InpLadder1_CloseFrac * 100.0,
               InpLadder2_Pct, InpLadder2_CloseFrac * 100.0,
               (InpUseLadder3 ? "sim" : "nao/softlock"),
               InpSL_ATR_Mult, InpMaxSL_CapitalPct, InpDailyLossPercent);
   PrintFormat("sem teto de trades/dia | softLock arm=%.2fxATR trail=%.2fxATR",
               InpSoftStart_ATR, InpTrail_ATR);
   UpdateChartComment();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   if(hEMA50  != INVALID_HANDLE) IndicatorRelease(hEMA50);
   if(hEMA200 != INVALID_HANDLE) IndicatorRelease(hEMA200);
   if(hADX    != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hATR    != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hVol    != INVALID_HANDLE) IndicatorRelease(hVol);
}

//+------------------------------------------------------------------+
void OnTick()
{
   ResetDayIfNeeded();
   UpdateChartComment();

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return;

   datetime now = TimeTradeServer();

   if(CountOurPositions() > 0 && !ShouldFlat(now) && !g_dayStopped)
      ManageLadderAndSoftLock();

   if(ShouldFlat(now))
   {
      if(CountOurPositions() > 0)
         CloseAllOurs("flat_hour");
      return;
   }

   if(DailyLossHit() || g_dayStopped)
   {
      g_dayStopped = true;
      if(!g_loggedDailyFlat)
      {
         PrintFormat("ScalpWIN2: STOP DIÁRIO 10%% | dayPnL=R$%.2f | limite=R$%.2f | base=R$%.2f → sem novas entradas",
                     DayPnLMoney(), DailyLossLimitMoney(), g_dayStartEquity);
         g_loggedDailyFlat = true;
      }
      if(InpFlatOnDailyLoss && CountOurPositions() > 0)
         CloseAllOurs("daily_loss");
      return;
   }

   if(!SessionOpen(now))
      return;

   // Gerencia posição; só avalia nova entrada em barra nova
   datetime barTime = iTime(_Symbol, InpTF, 1);
   if(barTime == 0 || barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;

   if(CountOurPositions() >= InpMaxPositions)
   {
      LogSkip(StringFormat("posição aberta (%d)", CountOurPositions()));
      return;
   }

   int dir = 0;
   if(!GetSignal(dir) || dir == 0)
      return;

   OpenTrade(dir);
}

//+------------------------------------------------------------------+
