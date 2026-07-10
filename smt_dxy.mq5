//+------------------------------------------------------------------+
//|                                                  SMT with DXY.mq5 |
//|                                 SMT Divergence vs DXY for MT5    |
//|              Integrated synthetic USDX from usdx.mq5              |
//+------------------------------------------------------------------+
#property copyright "SMT DXY"
#property version   "1.10"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   0

//+------------------------------------------------------------------+
//| Inputs                                                             |
//+------------------------------------------------------------------+
input bool     ShowDXYPanel    = true;          // Show DXY Panel
input bool     ShowLabels      = true;          // Show Divergence Labels
input bool     ShowLines       = true;          // Show Swing Point Lines
input int      PivotLen       = 5;              // Pivot Length

// ---- Synthetic USDX inputs (from usdx.mq5) -------------------------
input string   InpSrcType     = "Auto";          // "Auto", "Real", "Synthetic"
input int      InpSmoothLen   = 14;              // Synthetic EMA smoothing
input string   InpDXYSymbol   = "";              // DXY Symbol (auto if empty)

// ---- Fixed weights/bases from usdx.mq5 -----------------------------
double weightEUR = 0.576;
double weightJPY = 0.136;
double weightGBP = 0.119;
double weightCAD = 0.091;
double weightSEK = 0.042;
double weightCHF = 0.036;

double baseEURUSD = 1.08;
double baseUSDJPY = 150.0;
double baseGBPUSD = 1.27;
double baseUSDCAD = 1.36;
double baseUSDSEK = 10.5;
double baseUSDCHF = 0.88;

//+------------------------------------------------------------------+
//| DXY symbol list                                                   |
//+------------------------------------------------------------------+
string DXYSymbols[] = {"DX-Y.NYB", "USDX", "DXY", "USDOLLAR", "USDINDEX", "US.DX", "DX"};
string gDXYSymbol = "";
bool   gDxyAvailable = false;
bool   gUseSynthetic = false;

//+------------------------------------------------------------------+
//| Global state                                                        |
//+------------------------------------------------------------------+
double   gBuf[];
string   gPrefix;
datetime gLastBarTime = 0;

// Swing High state
double   gSHPrice  = 0, gPrevSHPrice  = 0;
datetime gSHTime   = 0, gPrevSHTime   = 0;

// Swing Low state
double   gSLPrice  = 0, gPrevSLPrice  = 0;
datetime gSLTime   = 0, gPrevSLTime   = 0;

// DXY Swing High state
double   gDSHPrice  = 0, gPrevDSHPrice  = 0;
datetime gDSHTime   = 0, gPrevDSHTime   = 0;

// DXY Swing Low state
double   gDSLPrice  = 0, gPrevDSLPrice  = 0;
datetime gDSLTime   = 0, gPrevDSLTime   = 0;

//+------------------------------------------------------------------+
//| Synthetic DXY arrays (global, persistent)                         |
//+------------------------------------------------------------------+
double gSynC[], gSynH[], gSynL[];
double gSynRawC[], gSynRawH[], gSynRawL[];
double gSynSmoothC[], gSynSmoothH[], gSynSmoothL[];

//+------------------------------------------------------------------+
//| Price helpers (from usdx.mq5)                                     |
//+------------------------------------------------------------------+
bool GetClose(const string symbol, const int shift, double &out_price)
{
   if(!SymbolSelect(symbol, true))
      return false;
   double arr[1];
   if(CopyClose(symbol, PERIOD_CURRENT, shift, 1, arr) != 1)
      return false;
   if(arr[0] == 0.0)
      return false;
   out_price = arr[0];
   return true;
}

bool GetHigh(const string symbol, const int shift, double &out_price)
{
   if(!SymbolSelect(symbol, true))
      return false;
   double arr[1];
   if(CopyHigh(symbol, PERIOD_CURRENT, shift, 1, arr) != 1)
      return false;
   if(arr[0] == 0.0)
      return false;
   out_price = arr[0];
   return true;
}

bool GetLow(const string symbol, const int shift, double &out_price)
{
   if(!SymbolSelect(symbol, true))
      return false;
   double arr[1];
   if(CopyLow(symbol, PERIOD_CURRENT, shift, 1, arr) != 1)
      return false;
   if(arr[0] == 0.0)
      return false;
   out_price = arr[0];
   return true;
}

//+------------------------------------------------------------------+
//| EMA (from usdx.mq5)                                              |
//+------------------------------------------------------------------+
double EMA(const double prev_ema, const double price, const int len)
{
   double alpha = 2.0 / (len + 1.0);
   return prev_ema + alpha * (price - prev_ema);
}

//+------------------------------------------------------------------+
//| Synthetic USDX for one bar (close)                                |
//+------------------------------------------------------------------+
double CalcSynUSDX(const int priceTypeEURGBP, const int priceTypeOthers, const int shift)
{
   double eurusd=0.0, usdjpy=0.0, gbpusd=0.0, usdcad=0.0, usdsek=0.0, usdchf=0.0;

   if(priceTypeEURGBP == PRICE_LOW)
   {
      GetLow("EURUSD", shift, eurusd);
      GetLow("GBPUSD", shift, gbpusd);
   }
   else
   {
      GetHigh("EURUSD", shift, eurusd);
      GetHigh("GBPUSD", shift, gbpusd);
   }

   if(priceTypeOthers == PRICE_HIGH)
   {
      GetHigh("USDJPY", shift, usdjpy);
      GetHigh("USDCAD", shift, usdcad);
      GetHigh("USDSEK", shift, usdsek);
      GetHigh("USDCHF", shift, usdchf);
   }
   else
   {
      GetLow("USDJPY", shift, usdjpy);
      GetLow("USDCAD", shift, usdcad);
      GetLow("USDSEK", shift, usdsek);
      GetLow("USDCHF", shift, usdchf);
   }

   double raw = 0.0;
   double wsum = 0.0;
   if(eurusd > 0) { raw += 100.0 * (baseEURUSD / eurusd) * weightEUR; wsum += weightEUR; }
   if(usdjpy > 0) { raw += 100.0 * (usdjpy / baseUSDJPY) * weightJPY; wsum += weightJPY; }
   if(gbpusd > 0) { raw += 100.0 * (baseGBPUSD / gbpusd) * weightGBP; wsum += weightGBP; }
   if(usdcad > 0) { raw += 100.0 * (usdcad / baseUSDCAD) * weightCAD; wsum += weightCAD; }
   if(usdsek > 0) { raw += 100.0 * (usdsek / baseUSDSEK) * weightSEK; wsum += weightSEK; }
   if(usdchf > 0) { raw += 100.0 * (usdchf / baseUSDCHF) * weightCHF; wsum += weightCHF; }

   if(wsum == 0.0) return 0.0;
   return raw / wsum;
}

//+------------------------------------------------------------------+
//| Build synthetic DXY arrays from 6-currency basket                 |
//+------------------------------------------------------------------+
void BuildSyntheticArrays(const int total)
{
   ArrayResize(gSynRawC, total);
   ArrayResize(gSynRawH, total);
   ArrayResize(gSynRawL, total);
   ArrayResize(gSynSmoothC, total);
   ArrayResize(gSynSmoothH, total);
   ArrayResize(gSynSmoothL, total);
   ArrayResize(gSynC, total);
   ArrayResize(gSynH, total);
   ArrayResize(gSynL, total);

   ArraySetAsSeries(gSynRawC, true);
   ArraySetAsSeries(gSynRawH, true);
   ArraySetAsSeries(gSynRawL, true);
   ArraySetAsSeries(gSynSmoothC, true);
   ArraySetAsSeries(gSynSmoothH, true);
   ArraySetAsSeries(gSynSmoothL, true);
   ArraySetAsSeries(gSynC, true);
   ArraySetAsSeries(gSynH, true);
   ArraySetAsSeries(gSynL, true);

   for(int shift = total - 1; shift >= 0; shift--)
   {
      double eurusd=0.0, usdjpy=0.0, gbpusd=0.0, usdcad=0.0, usdsek=0.0, usdchf=0.0;
      bool gE = GetClose("EURUSD", shift, eurusd);
      bool gJ = GetClose("USDJPY", shift, usdjpy);
      bool gG = GetClose("GBPUSD", shift, gbpusd);
      bool gC = GetClose("USDCAD", shift, usdcad);
      bool gS = GetClose("USDSEK", shift, usdsek);
      bool gF = GetClose("USDCHF", shift, usdchf);

      double rawC = 0.0;
      double wsum = 0.0;
      if(gE && eurusd>0) { rawC += 100.0*(baseEURUSD/eurusd)*weightEUR; wsum+=weightEUR; }
      if(gJ && usdjpy>0) { rawC += 100.0*(usdjpy/baseUSDJPY)*weightJPY; wsum+=weightJPY; }
      if(gG && gbpusd>0) { rawC += 100.0*(baseGBPUSD/gbpusd)*weightGBP; wsum+=weightGBP; }
      if(gC && usdcad>0) { rawC += 100.0*(usdcad/baseUSDCAD)*weightCAD; wsum+=weightCAD; }
      if(gS && usdsek>0) { rawC += 100.0*(usdsek/baseUSDSEK)*weightSEK; wsum+=weightSEK; }
      if(gF && usdchf>0) { rawC += 100.0*(usdchf/baseUSDCHF)*weightCHF; wsum+=weightCHF; }
      gSynRawC[shift] = (wsum>0) ? rawC/wsum : 0.0;

      gSynRawH[shift] = CalcSynUSDX(PRICE_LOW, PRICE_HIGH, shift);
      gSynRawL[shift] = CalcSynUSDX(PRICE_HIGH, PRICE_LOW, shift);

      if(gSynRawC[shift]==0.0 && shift+1<total && gSynRawC[shift+1]!=0.0)
         gSynRawC[shift] = gSynRawC[shift+1];
      if(gSynRawH[shift]==0.0 && shift+1<total && gSynRawH[shift+1]!=0.0)
         gSynRawH[shift] = gSynRawH[shift+1];
      if(gSynRawL[shift]==0.0 && shift+1<total && gSynRawL[shift+1]!=0.0)
         gSynRawL[shift] = gSynRawL[shift+1];
   }

   for(int i = total - 1; i >= 0; i--)
   {
      if(gSynRawC[i]==0.0)
         gSynSmoothC[i]=0.0;
      else if(i==total-1 || gSynSmoothC[i+1]==0.0)
         gSynSmoothC[i]=gSynRawC[i];
      else
         gSynSmoothC[i]=EMA(gSynSmoothC[i+1], gSynRawC[i], InpSmoothLen);

      if(gSynRawH[i]==0.0)
         gSynSmoothH[i]=0.0;
      else if(i==total-1 || gSynSmoothH[i+1]==0.0)
         gSynSmoothH[i]=gSynRawH[i];
      else
         gSynSmoothH[i]=EMA(gSynSmoothH[i+1], gSynRawH[i], InpSmoothLen);

      if(gSynRawL[i]==0.0)
         gSynSmoothL[i]=0.0;
      else if(i==total-1 || gSynSmoothL[i+1]==0.0)
         gSynSmoothL[i]=gSynRawL[i];
      else
         gSynSmoothL[i]=EMA(gSynSmoothL[i+1], gSynRawL[i], InpSmoothLen);
   }

   for(int i = 0; i < total; i++)
   {
      gSynC[i] = gSynSmoothC[i];
      gSynH[i] = gSynSmoothH[i];
      gSynL[i] = gSynSmoothL[i];
   }
}

//+------------------------------------------------------------------+
//| Check if a symbol is known to the terminal                        |
//+------------------------------------------------------------------+
bool IsSymbolKnown(string symbolName)
{
   int total = SymbolsTotal(true);
   for(int i = 0; i < total; i++)
   {
      if(SymbolName(i, true) == symbolName)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Find DXY symbol in terminal                                       |
//+------------------------------------------------------------------+
string FindDXYSymbol()
{
   if(InpDXYSymbol != "")
   {
      string userSym = InpDXYSymbol;
      StringTrimRight(userSym);
      StringTrimLeft(userSym);
      if(IsSymbolKnown(userSym))
         return userSym;
      Print("User-specified symbol '", userSym, "' not found.");
   }

   int total = SymbolsTotal(true);
   for(int i = 0; i < total; i++)
   {
      string name = SymbolName(i, true);
      for(int j = 0; j < ArraySize(DXYSymbols); j++)
      {
         if(name == DXYSymbols[j])
            return name;
      }
   }

   string partials[] = {"DXY", "DX", "USDX", "US.DX", "USDOLLAR", "USDINDEX", "DOLLAR"};
   for(int i = 0; i < total; i++)
   {
      string name = SymbolName(i, true);
      for(int j = 0; j < ArraySize(partials); j++)
      {
         if(StringFind(name, partials[j]) >= 0)
            return name;
      }
   }

   return "";
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   gPrefix = "SMT_DXY_" + IntegerToString(ChartID()) + "_";

   SetIndexBuffer(0, gBuf, INDICATOR_DATA);

   bool forceSyn = (InpSrcType == "Synthetic");

   if(!forceSyn)
   {
      gDXYSymbol = FindDXYSymbol();
      if(gDXYSymbol != "")
      {
         if(!SymbolSelect(gDXYSymbol, true))
            Print("Warning: Could not add ", gDXYSymbol, " to Market Watch.");

         double test[1];
         gDxyAvailable = (CopyClose(gDXYSymbol, PERIOD_CURRENT, 0, 1, test) == 1);

         if(gDxyAvailable)
         {
            Print("Using DXY symbol: ", gDXYSymbol);
         }
         else
         {
            Print("Cannot get data for ", gDXYSymbol);
            if(InpSrcType == "Real")
               return INIT_FAILED;
            gDXYSymbol = "";
         }
      }
      else
      {
         Print("No DXY symbol found.");
         if(InpSrcType == "Real")
            return INIT_FAILED;
      }
   }

   if(gDXYSymbol == "")
   {
      gUseSynthetic = true;
      Print("Using SYNTHETIC USDX (6-currency basket)");
   }

   if(gUseSynthetic)
      IndicatorSetString(INDICATOR_SHORTNAME, "SMT with DXY (Synthetic)");
   else
      IndicatorSetString(INDICATOR_SHORTNAME, "SMT with DXY (" + gDXYSymbol + ")");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinit                                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, gPrefix);
   Comment("");
}

//+------------------------------------------------------------------+
//| Swing helpers                                                     |
//+------------------------------------------------------------------+
bool IsSwingHigh(const double &src[], int l, int idx, int limit)
{
   if(idx - l < 0 || idx + l >= limit)
      return false;
   double v = src[idx];
   for(int i = -l; i <= l; i++)
   {
      if(src[idx + i] > v)
         return false;
   }
   return true;
}

bool IsSwingLow(const double &src[], int l, int idx, int limit)
{
   if(idx - l < 0 || idx + l >= limit)
      return false;
   double v = src[idx];
   for(int i = -l; i <= l; i++)
   {
      if(src[idx + i] < v)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Update the swing state                                            |
//+------------------------------------------------------------------+
void UpdateSwingState(const double &mainH[], const double &mainL[],
                     const double &dxyH[], const double &dxyL[],
                     const datetime &time[], int pos, int limit)
{
   if(IsSwingHigh(mainH, PivotLen, pos, limit))
   {
      gPrevSHPrice = gSHPrice;
      gPrevSHTime  = gSHTime;
      gSHPrice  = mainH[pos];
      gSHTime   = time[pos];
   }
   if(IsSwingLow(mainL, PivotLen, pos, limit))
   {
      gPrevSLPrice = gSLPrice;
      gPrevSLTime  = gSLTime;
      gSLPrice  = mainL[pos];
      gSLTime   = time[pos];
   }
   if(IsSwingHigh(dxyH, PivotLen, pos, limit))
   {
      gPrevDSHPrice = gDSHPrice;
      gPrevDSHTime  = gDSHTime;
      gDSHPrice  = dxyH[pos];
      gDSHTime   = time[pos];
   }
   if(IsSwingLow(dxyL, PivotLen, pos, limit))
   {
      gPrevDSLPrice = gDSLPrice;
      gPrevDSLTime  = gDSLTime;
      gDSLPrice  = dxyL[pos];
      gDSLTime   = time[pos];
   }
}

//+------------------------------------------------------------------+
//| Delete old objects                                                |
//+------------------------------------------------------------------+
void CleanObjects(const string pref, datetime since)
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, pref) != 0)
         continue;
      datetime t = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
      if(t < since)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| OnCalculate                                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &_time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < PivotLen * 2 + 1)
      return 0;

   // Fetch OHLC for main symbol as series-indexed arrays
   double mainH[], mainL[];
   ArraySetAsSeries(mainH, true);
   ArraySetAsSeries(mainL, true);
   if(CopyHigh(Symbol(), Period(), 0, rates_total, mainH) <= 0) return 0;
   if(CopyLow(Symbol(), Period(), 0, rates_total, mainL) <= 0) return 0;

   datetime time[];
   ArraySetAsSeries(time, true);
   if(CopyTime(Symbol(), Period(), 0, rates_total, time) <= 0) return 0;

   // Get DXY data
   double dxyC[], dxyH[], dxyL[];

   if(gUseSynthetic)
   {
      BuildSyntheticArrays(rates_total);
      ArrayCopy(dxyC, gSynC, 0, 0, WHOLE_ARRAY);
      ArrayCopy(dxyH, gSynH, 0, 0, WHOLE_ARRAY);
      ArrayCopy(dxyL, gSynL, 0, 0, WHOLE_ARRAY);
      ArraySetAsSeries(dxyC, true);
      ArraySetAsSeries(dxyH, true);
      ArraySetAsSeries(dxyL, true);
   }
   else
   {
      ArraySetAsSeries(dxyC, true);
      ArraySetAsSeries(dxyH, true);
      ArraySetAsSeries(dxyL, true);
      if(CopyClose(gDXYSymbol, Period(), 0, rates_total, dxyC) <= 0) return 0;
      if(CopyHigh(gDXYSymbol, Period(), 0, rates_total, dxyH) <= 0) return 0;
      if(CopyLow(gDXYSymbol, Period(), 0, rates_total, dxyL) <= 0) return 0;
   }

   int limit = rates_total;

   // First run: scan entire history
   if(prev_calculated == 0)
   {
      gSHPrice = gSLPrice = gDSHPrice = gDSLPrice = 0;
      gPrevSHPrice = gPrevSLPrice = gPrevDSHPrice = gPrevDSLPrice = 0;
      gSHTime = gSLTime = gDSHTime = gDSLTime = 0;

      for(int i = limit - PivotLen - 1; i >= PivotLen; i--)
         UpdateSwingState(mainH, mainL, dxyH, dxyL, time, i, limit);
   }

   int start = rates_total - 1;
   if(prev_calculated > 1)
      start = prev_calculated;

   // Process new bar(s)
   for(int i = start; i < limit; i++)
   {
      int pos = limit - 1 - i;
      if(pos < PivotLen || pos >= limit)
         continue;

      if(time[pos] == gLastBarTime)
         continue;

      datetime curTime = time[pos];
      bool bearishSMT  = false;
      bool bullishSMT  = false;

      if(gPrevSHPrice > 0 && gPrevDSHPrice > 0)
         bearishSMT = (gSHPrice > gPrevSHPrice && gDSHPrice < gPrevDSHPrice);
      if(gPrevSLPrice > 0 && gPrevDSLPrice > 0)
         bullishSMT = (gSLPrice < gPrevSLPrice && gDSLPrice > gPrevDSLPrice);

      if(ShowLines && bearishSMT && gPrevSHPrice > 0 && gPrevDSHPrice > 0)
      {
         string ln1 = gPrefix + "bm_" + IntegerToString(gSHTime);
         ObjectCreate(0, ln1, OBJ_TREND, 0, gPrevSHTime, gPrevSHPrice, gSHTime, gSHPrice);
         ObjectSetInteger(0, ln1, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, ln1, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, ln1, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, ln1, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, ln1, OBJPROP_BACK, true);

         string ln2 = gPrefix + "bd_" + IntegerToString(gSHTime);
         ObjectCreate(0, ln2, OBJ_TREND, 0, gPrevDSHTime, gPrevDSHPrice, gDSHTime, gDSHPrice);
         ObjectSetInteger(0, ln2, OBJPROP_COLOR, clrGreen);
         ObjectSetInteger(0, ln2, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, ln2, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, ln2, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, ln2, OBJPROP_BACK, true);
      }

      if(ShowLines && bullishSMT && gPrevSLPrice > 0 && gPrevDSLPrice > 0)
      {
         string ln1 = gPrefix + "gm_" + IntegerToString(gSLTime);
         ObjectCreate(0, ln1, OBJ_TREND, 0, gPrevSLTime, gPrevSLPrice, gSLTime, gSLPrice);
         ObjectSetInteger(0, ln1, OBJPROP_COLOR, clrGreen);
         ObjectSetInteger(0, ln1, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, ln1, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, ln1, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, ln1, OBJPROP_BACK, true);

         string ln2 = gPrefix + "gd_" + IntegerToString(gSLTime);
         ObjectCreate(0, ln2, OBJ_TREND, 0, gPrevDSLTime, gPrevDSLPrice, gDSLTime, gDSLPrice);
         ObjectSetInteger(0, ln2, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, ln2, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, ln2, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, ln2, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, ln2, OBJPROP_BACK, true);
      }

      if(ShowLabels)
      {
         if(bearishSMT)
         {
            string lbl = gPrefix + "lb_" + IntegerToString(gSHTime);
            ObjectCreate(0, lbl, OBJ_TEXT, 0, gSHTime, mainH[pos] + 2 * Point());
            ObjectSetString(0, lbl, OBJPROP_TEXT, "SMT Bearish");
            ObjectSetInteger(0, lbl, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
         }
         if(bullishSMT)
         {
            string lbl = gPrefix + "lg_" + IntegerToString(gSLTime);
            ObjectCreate(0, lbl, OBJ_TEXT, 0, gSLTime, mainL[pos] - 2 * Point());
            ObjectSetString(0, lbl, OBJPROP_TEXT, "SMT Bullish");
            ObjectSetInteger(0, lbl, OBJPROP_COLOR, clrGreen);
            ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_TOP);
         }
      }

      if(bearishSMT)
         Alert("Bearish SMT Divergence: ", Symbol(), " vs ", (gUseSynthetic ? "SynthUSDX" : gDXYSymbol));
      if(bullishSMT)
         Alert("Bullish SMT Divergence: ", Symbol(), " vs ", (gUseSynthetic ? "SynthUSDX" : gDXYSymbol));

      UpdateSwingState(mainH, mainL, dxyH, dxyL, time, pos, limit);

      if(pos % 5 == 0)
      {
         datetime oldBar = time[pos] - 300 * PeriodSeconds(Period());
         if(oldBar > 0)
            CleanObjects(gPrefix, oldBar);
      }

      gLastBarTime = curTime;
   }

   // DXY Panel
   if(ShowDXYPanel && limit > 0)
   {
      if(gUseSynthetic)
      {
         if(gSynC[0] > 0)
         {
            double dxyC0 = gSynC[0];
            double dxyC1 = (gSynC[1] > 0) ? gSynC[1] : dxyC0;
            double chg = (dxyC0 - dxyC1) / dxyC1 * 100.0;
            string txt = StringFormat("SynthUSDX: %.2f (%+.2f%%)", dxyC0, chg);
            Comment(txt);
         }
      }
      else
      {
         if(dxyC[0] > 0)
         {
            double dxyC0 = dxyC[0];
            double dxyC1 = (dxyC[1] > 0) ? dxyC[1] : dxyC0;
            double chg = (dxyC0 - dxyC1) / dxyC1 * 100.0;
            string txt = StringFormat("DXY: %.2f (%+.2f%%)", dxyC0, chg);
            Comment(txt);
         }
      }
   }
   else
   {
      Comment("");
   }

   return rates_total;
}
//+------------------------------------------------------------------+
