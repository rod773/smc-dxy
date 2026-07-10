//+------------------------------------------------------------------+
//|                                                USDX Strength   |
//|                           NZD/AUD Strength Meter (MT5/MQL5)    |
//|  Converted from Pine Script: smartmoney_fibonacci (USDX v6)     |
//+------------------------------------------------------------------+
#property indicator_separate_window
#property indicator_buffers 6
#property indicator_plots   3
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_label1  "USDX"
#property indicator_width1  2
#property indicator_type2   DRAW_FILLING
#property indicator_label2  "Overbought Zone"
#property indicator_color2  clrAqua
#property indicator_type3   DRAW_FILLING
#property indicator_label3  "Oversold Zone"
#property indicator_color3  clrAqua

// ---- Input parameters (match Pine where applicable) -----------------
input string InpSrcType = "Synthetic"; // "DXY" or "Synthetic"

input int    InpSmoothLen   = 14; // EMA smoothing length
input double InpStrongThresh= 1.5; // Strong threshold (StDev)
input double InpWeakThresh  = 0.8; // Weak threshold (StDev)

input color  InpColBull     = clrLime; // #15b879 - used when USD weak (z < -weak)
input color  InpColBear     = clrRed; // #dd621a - used when USD strong (z > weak)
input color  InpColNeutral  = clrYellow; // #787b86
input color  InpColStrong   = clrAqua; // #9c27b0 - fill zones

// ---- Fixed weights/bases from Pine ---------------------------------
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

// ---- Color index mapping ------------------------------------------
// 0 = Neutral, 1 = Bull (USD moderately strong), 2 = Bear (USD weak), 3 = Strong
#define COL_NEUTRAL 0
#define COL_BULL    1
#define COL_BEAR    2
#define COL_STRONG  3

// ---- Indicator buffers ---------------------------------------------
double bUSDX[];      // data
double bColor[];     // color index
double bUpperWeak[];  // mean + weak*stdev
double bUpperStrong[];// mean + strong*stdev
double bLowerWeak[];  // mean - weak*stdev
double bLowerStrong[];// mean - strong*stdev

// ---- Internal buffers for computation ------------------------------
double usdx_raw[];
double usdx_smooth[];
double mean_arr[];
double stdev_arr[];
double z_arr[];

// ---- Utility: fetch close for a symbol at a given shift ----------
bool GetClose(const string symbol, const int shift, double &out_price)
{
   // Make sure the symbol is available in the terminal.
   if(!SymbolSelect(symbol, true))
      return false;

   double arr[1];
   // CopyClose with start_pos = shift (0 = most recent bar), count = 1.
   if(CopyClose(symbol, _Period, shift, 1, arr) != 1)
      return false;

   if(arr[0] == 0.0)
      return false;

   out_price = arr[0];
   return true;
}

// ---- EMA -----------------------------------------------------------
double EMA(const double prev_ema, const double price, const int len)
{
   double alpha = 2.0 / (len + 1.0);
   return prev_ema + alpha * (price - prev_ema);
}

// ----+----------------------------------------------------------------
int OnInit()
{
   SetIndexBuffer(0, bUSDX, INDICATOR_DATA);
   SetIndexBuffer(1, bColor, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, bUpperWeak, INDICATOR_DATA);    // plot 2 (Overbought) lower bound
   SetIndexBuffer(3, bUpperStrong, INDICATOR_DATA);  // plot 2 (Overbought) upper bound
   SetIndexBuffer(4, bLowerStrong, INDICATOR_DATA);  // plot 3 (Oversold) lower bound
   SetIndexBuffer(5, bLowerWeak, INDICATOR_DATA);    // plot 3 (Oversold) upper bound

   ArraySetAsSeries(bUSDX, true);
   ArraySetAsSeries(bColor, true);
   ArraySetAsSeries(bUpperWeak, true);
   ArraySetAsSeries(bUpperStrong, true);
   ArraySetAsSeries(bLowerWeak, true);
   ArraySetAsSeries(bLowerStrong, true);

   ArraySetAsSeries(usdx_smooth, true);
   ArraySetAsSeries(mean_arr, true);
   ArraySetAsSeries(stdev_arr, true);
   ArraySetAsSeries(z_arr, true);
   ArraySetAsSeries(usdx_raw, true);

   // Configure multi-color line plot.
   PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 4);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, COL_NEUTRAL, InpColNeutral);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, COL_BULL,    InpColBull);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, COL_BEAR,    InpColBear);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, COL_STRONG,  InpColStrong);

   IndicatorSetString(INDICATOR_SHORTNAME, "USDX Strength Meter [NZDAUD]");
   return(INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 200) return 0;

   ArrayResize(usdx_raw, rates_total);
   ArrayResize(usdx_smooth, rates_total);
   ArrayResize(mean_arr, rates_total);
   ArrayResize(stdev_arr, rates_total);
   ArrayResize(z_arr, rates_total);
   ArrayResize(bUSDX, rates_total);
   ArrayResize(bColor, rates_total);
   ArrayResize(bUpperWeak, rates_total);
   ArrayResize(bUpperStrong, rates_total);
   ArrayResize(bLowerWeak, rates_total);
   ArrayResize(bLowerStrong, rates_total);

   // Incremental recompute: only process new bars (plus one overlapping
   // bar for EMA/zscore continuity). Global buffers persist across calls.
   int start = (prev_calculated == 0) ? 0 : MathMax(0, prev_calculated - 1);

   // --- Raw USD index value per bar --------------------------------
   for(int shift = start; shift <= rates_total - 1; shift++)
   {
      double eurusd=0.0, usdjpy=0.0, gbpusd=0.0, usdcad=0.0, usdsek=0.0, usdchf=0.0;
      bool gE = GetClose("EURUSD", shift, eurusd);
      bool gJ = GetClose("USDJPY", shift, usdjpy);
      bool gG = GetClose("GBPUSD", shift, gbpusd);
      bool gC = GetClose("USDCAD", shift, usdcad);
      bool gS = GetClose("USDSEK", shift, usdsek);
      bool gF = GetClose("USDCHF", shift, usdchf);

      // Synthetic USD index: skip any component that isn't available and
      // renormalize so the result stays scaled around ~100.
      double raw = 0.0;
      double wsum = 0.0;
      if(gE && eurusd > 0) { raw += 100.0 * (baseEURUSD / eurusd) * weightEUR; wsum += weightEUR; }
      if(gJ && usdjpy > 0) { raw += 100.0 * (usdjpy / baseUSDJPY) * weightJPY; wsum += weightJPY; }
      if(gG && gbpusd > 0) { raw += 100.0 * (baseGBPUSD / gbpusd) * weightGBP; wsum += weightGBP; }
      if(gC && usdcad > 0) { raw += 100.0 * (usdcad / baseUSDCAD) * weightCAD; wsum += weightCAD; }
      if(gS && usdsek > 0) { raw += 100.0 * (usdsek / baseUSDSEK) * weightSEK; wsum += weightSEK; }
      if(gF && usdchf > 0) { raw += 100.0 * (usdchf / baseUSDCHF) * weightCHF; wsum += weightCHF; }

      bool has = (wsum > 0.0);
      if(has) raw = raw / wsum; // weights total 1.0 -> renormalize

      // DXY mode: prefer the real DXY/USDX symbol, else fall back to synthetic.
      if(InpSrcType == "DXY")
      {
         double dxyClose = 0.0;
         if(GetClose("DXY", shift, dxyClose) || GetClose("USDX", shift, dxyClose))
         {
            raw = dxyClose;
            has = true;
         }
      }

      // Forward-fill gaps (Pine: usdx := nz(rawDXY, nz(usdx[1], usdx))).
      if(!has)
      {
         if(shift + 1 <= rates_total - 1 && usdx_raw[shift + 1] != EMPTY_VALUE)
            raw = usdx_raw[shift + 1];
         else
            raw = EMPTY_VALUE;
         has = (raw != EMPTY_VALUE);
      }

      usdx_raw[shift] = has ? raw : EMPTY_VALUE;
   }

   // EMA smoothing (newest -> oldest; each bar uses the older bar's EMA).
   for(int shift = rates_total - 1; shift >= start; shift--)
   {
      if(usdx_raw[shift] == EMPTY_VALUE) { usdx_smooth[shift] = EMPTY_VALUE; continue; }

      if(shift == rates_total - 1 || usdx_smooth[shift + 1] == EMPTY_VALUE)
         usdx_smooth[shift] = usdx_raw[shift];
      else
         usdx_smooth[shift] = EMA(usdx_smooth[shift + 1], usdx_raw[shift], InpSmoothLen);
   }

   // SMA(50), stdev(50), zscore (newest -> oldest).
   int len = 50;
   for(int shift = rates_total - 1; shift >= start; shift--)
   {
      if(shift + len > rates_total - 1) { mean_arr[shift]=EMPTY_VALUE; stdev_arr[shift]=EMPTY_VALUE; z_arr[shift]=EMPTY_VALUE; continue; }
      if(usdx_smooth[shift] == EMPTY_VALUE) { mean_arr[shift]=EMPTY_VALUE; stdev_arr[shift]=EMPTY_VALUE; z_arr[shift]=EMPTY_VALUE; continue; }

      double sum=0.0; int okcnt=0;
      for(int i=0;i<len;i++)
      {
         double v = usdx_smooth[shift+i];
         if(v==EMPTY_VALUE) continue;
         sum += v; okcnt++;
      }
      if(okcnt!=len) { mean_arr[shift]=EMPTY_VALUE; stdev_arr[shift]=EMPTY_VALUE; z_arr[shift]=EMPTY_VALUE; continue; }

      double mean = sum / len;
      double sd=0.0;
      for(int i=0;i<len;i++)
      {
         double d = usdx_smooth[shift+i] - mean;
         sd += d*d;
      }
      sd = MathSqrt(sd / len);

      mean_arr[shift]=mean;
      stdev_arr[shift]=sd;
      if(sd>0.0) z_arr[shift] = (usdx_smooth[shift]-mean)/sd;
      else z_arr[shift]=EMPTY_VALUE;
   }

   // Overbought / oversold bands (Pine: upperStrong, upperWeak, lowerWeak, lowerStrong).
   for(int shift = start; shift <= rates_total - 1; shift++)
   {
      if(mean_arr[shift]==EMPTY_VALUE || stdev_arr[shift]==EMPTY_VALUE || stdev_arr[shift]<=0.0)
      {
         bUpperWeak[shift]   = EMPTY_VALUE;
         bUpperStrong[shift] = EMPTY_VALUE;
         bLowerWeak[shift]   = EMPTY_VALUE;
         bLowerStrong[shift] = EMPTY_VALUE;
      }
      else
      {
         double m = mean_arr[shift];
         double s = stdev_arr[shift];
         bUpperWeak[shift]   = m + InpWeakThresh   * s;
         bUpperStrong[shift] = m + InpStrongThresh * s;
         bLowerWeak[shift]   = m - InpWeakThresh   * s;
         bLowerStrong[shift] = m - InpStrongThresh * s;
      }
   }

   // --- Plot: draw the smoothed line for all bars; color by zscore.
   for(int shift = start; shift <= rates_total - 1; shift++)
   {
      if(usdx_smooth[shift] == EMPTY_VALUE)
      {
         bUSDX[shift]  = EMPTY_VALUE;
         bColor[shift] = EMPTY_VALUE;
         continue;
      }

      bUSDX[shift] = usdx_smooth[shift];

      int col = COL_NEUTRAL;
      if(z_arr[shift] != EMPTY_VALUE)
      {
         double z = z_arr[shift];
         if(z > InpWeakThresh)        col = COL_BEAR;   // strong USD  -> Bear color
         else if(z < -InpWeakThresh)  col = COL_BULL;   // weak USD    -> Bull color
         else                         col = COL_NEUTRAL;
      }
      bColor[shift] = col;
   }

   // --- Alerts (crossovers/crossunders) -----------------------------
   int s0=0, s1=1;
   if(rates_total>60 && z_arr[s0]!=EMPTY_VALUE && z_arr[s1]!=EMPTY_VALUE)
   {
      double z0=z_arr[s0], z1=z_arr[s1];

      bool alertStrongOverbought = (z1<=InpStrongThresh && z0>InpStrongThresh);
      bool alertStrongOversold   = (z1>=-InpStrongThresh && z0<-InpStrongThresh);

      // Divergences: usdFromNZD = 1/NZDUSD and compare with SMA(20) and zScore>0.5
      double nzdusd=0.0, audusd=0.0;
      bool okN = GetClose("NZDUSD", s0, nzdusd);
      bool okA = GetClose("AUDUSD", s0, audusd);

      double usdFromNZD = (okN && nzdusd>0)? 1.0/nzdusd : EMPTY_VALUE;
      double usdFromAUD = (okA && audusd>0)? 1.0/audusd : EMPTY_VALUE;

      int smaLen = 20;
      double smaUSDNZD = EMPTY_VALUE;
      double smaUSDAUD = EMPTY_VALUE;

      if(usdFromNZD!=EMPTY_VALUE)
      {
         double sum=0.0; int cnt=0;
         for(int i=0;i<smaLen;i++)
         {
            double x=0.0;
            if(GetClose("NZDUSD", s0+i, x) && x>0)
            {
               sum += 1.0/x;
               cnt++;
            }
         }
         if(cnt==smaLen) smaUSDNZD = sum/smaLen;
      }

      if(usdFromAUD!=EMPTY_VALUE)
      {
         double sum=0.0; int cnt=0;
         for(int i=0;i<smaLen;i++)
         {
            double x=0.0;
            if(GetClose("AUDUSD", s0+i, x) && x>0)
            {
               sum += 1.0/x;
               cnt++;
            }
         }
         if(cnt==smaLen) smaUSDAUD = sum/smaLen;
      }

      bool nzdDivergence = false;
      bool audDivergence = false;
      if(usdFromNZD!=EMPTY_VALUE && smaUSDNZD!=EMPTY_VALUE && z_arr[s0]>0.5 && z_arr[s1]!=EMPTY_VALUE)
      {
         double nzdusd_prev=0.0;
         bool okNprev = GetClose("NZDUSD", s1, nzdusd_prev);
         double usdFromNZD_prev = (okNprev && nzdusd_prev>0)? 1.0/nzdusd_prev : EMPTY_VALUE;
         double smaUSDNZD_prev = EMPTY_VALUE;
         if(usdFromNZD_prev!=EMPTY_VALUE)
         {
            double sum=0.0; int cnt=0;
            for(int i=0;i<smaLen;i++)
            {
               double x=0.0;
               if(GetClose("NZDUSD", s1+i, x) && x>0)
               {
                  sum += 1.0/x;
                  cnt++;
               }
            }
            if(cnt==smaLen) smaUSDNZD_prev = sum/smaLen;
         }

         if(usdFromNZD_prev!=EMPTY_VALUE && smaUSDNZD_prev!=EMPTY_VALUE)
            nzdDivergence = (usdFromNZD_prev<=smaUSDNZD_prev && usdFromNZD>smaUSDNZD);
      }

      if(usdFromAUD!=EMPTY_VALUE && smaUSDAUD!=EMPTY_VALUE && z_arr[s0]>0.5 && z_arr[s1]!=EMPTY_VALUE)
      {
         double audusd_prev=0.0;
         bool okAprev = GetClose("AUDUSD", s1, audusd_prev);
         double usdFromAUD_prev = (okAprev && audusd_prev>0)? 1.0/audusd_prev : EMPTY_VALUE;
         double smaUSDAUD_prev = EMPTY_VALUE;
         if(usdFromAUD_prev!=EMPTY_VALUE)
         {
            double sum=0.0; int cnt=0;
            for(int i=0;i<smaLen;i++)
            {
               double x=0.0;
               if(GetClose("AUDUSD", s1+i, x) && x>0)
               {
                  sum += 1.0/x;
                  cnt++;
               }
            }
            if(cnt==smaLen) smaUSDAUD_prev = sum/smaLen;
         }

         if(usdFromAUD_prev!=EMPTY_VALUE && smaUSDAUD_prev!=EMPTY_VALUE)
            audDivergence = (usdFromAUD_prev<=smaUSDAUD_prev && usdFromAUD>smaUSDAUD);
      }

     /* if(alertStrongOverbought)
         //Alert("USDX Strongly Overbought: zScore crossed above strong threshold");
      if(alertStrongOversold)
         //Alert("USDX Strongly Oversold: zScore crossed below -strong threshold");
      if(nzdDivergence)
         //Alert("NZDUSD Divergence: NZD weakness vs USDX strength (usdFromNZD crossed above SMA, zScore>0.5)");
      if(audDivergence)
         //Alert("AUDUSD Divergence: AUD weakness vs USDX strength (usdFromAUD crossed above SMA, zScore>0.5)");*/
   }

   return(rates_total);
}
