//+------------------------------------------------------------------+
//|                                     LarryWilliams_MarketStructure.mq5 |
//|                                         Larry Williams: Market Structure |
//+------------------------------------------------------------------+
#property copyright "Copyright Smollet"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

input bool ShowIntermediateTrend = true; // Show Intermediate Trend Icons

double swHiHighs[];
double swHiLows[];
double swLowHighs[];
double swLowLows[];

double imTops[];
double imBots[];

datetime hTime = 0;
datetime lTime = 0;

int swDir = 1;
int imDir = 1;

int prevHiSize = 0;
int prevLowSize = 0;

bool inited = false;

//+------------------------------------------------------------------+
void ArrUnshift(double &a[], double v)
{
    int n = ArraySize(a);
    ArrayResize(a, n + 1);
    for(int i = n; i > 0; i--) a[i] = a[i - 1];
    a[0] = v;
}
//+------------------------------------------------------------------+
double ArrFirst(const double &a[])
{
    return (ArraySize(a) > 0) ? a[0] : 0;
}
//+------------------------------------------------------------------+
int OnInit()
{
    return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int r)
{
    ObjectsDeleteAll(0, "LW_");
}
//+------------------------------------------------------------------+
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
    if(rates_total < 1) return 0;

    if(prev_calculated == 0)
    {
        ArrayResize(swHiHighs, 0);
        ArrayResize(swHiLows, 0);
        ArrayResize(swLowHighs, 0);
        ArrayResize(swLowLows, 0);
        ArrayResize(imTops, 0);
        ArrayResize(imBots, 0);
        hTime = 0; lTime = 0;
        swDir = 1; imDir = 1;
        prevHiSize = 0; prevLowSize = 0;
        inited = false;
        ObjectsDeleteAll(0, "LW_");
    }

    if(!inited && rates_total > 0)
    {
        ArrUnshift(swHiHighs, high[0]);
        ArrUnshift(swLowHighs, high[0]);
        hTime = time[0];
        lTime = time[0];
        prevHiSize = 1;
        prevLowSize = 1;
        inited = true;
    }

    int start = prev_calculated;
    if(start < 1) start = 1;

    for(int i = start; i < rates_total; i++)
    {
        double hi = high[i];
        double lo = low[i];
        datetime ti = time[i];
        int swDirPrev = swDir;

        //--- Add swing high in uptrend
        if(ArraySize(swHiHighs) > 0 && hi > ArrFirst(swHiHighs) && swDir == 1)
        {
            ArrUnshift(swHiHighs, hi);
            ArrUnshift(swHiLows, lo);
            hTime = ti;
        }

        //--- Add swing low in downtrend
        if(ArraySize(swLowLows) > 0 && lo < ArrFirst(swLowLows) && swDir == -1)
        {
            ArrUnshift(swLowHighs, hi);
            ArrUnshift(swLowLows, lo);
            lTime = ti;
        }

        //--- Trend change: up -> down
        if(ArraySize(swHiLows) > 0 && swDir == 1 && lo < ArrFirst(swHiLows))
        {
            swDir = -1;
            ArrUnshift(swLowHighs, hi);
            ArrUnshift(swLowLows, lo);
            lTime = ti;
        }

        //--- Trend change: down -> up
        if(ArraySize(swHiHighs) > 0 && swDir == -1 && swDirPrev == -1 && hi > ArrFirst(swLowHighs))
        {
            swDir = 1;
            ArrUnshift(swHiHighs, hi);
            ArrUnshift(swHiLows, lo);
            hTime = ti;
        }

        //--- Draw up line (down -> up trend change)
        if(swDir == 1 && swDirPrev == -1 && ArraySize(swLowLows) > 0)
        {
            ObjectDelete(0, "LW_UP");
            ObjectCreate(0, "LW_UP", OBJ_TREND, 0, lTime, ArrFirst(swLowLows), ti, ArrFirst(swHiHighs));
            ObjectSetInteger(0, "LW_UP", OBJPROP_COLOR, clrGreen);
            ObjectSetInteger(0, "LW_UP", OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, "LW_UP", OBJPROP_RAY_RIGHT, true);

            ObjectSetDouble(0, "LW_DN", OBJPROP_PRICE, 1, ArrFirst(swLowLows));
            ObjectSetInteger(0, "LW_DN", OBJPROP_TIME, 1, lTime);
        }

        //--- Draw down line (up -> down trend change)
        if(swDir == -1 && swDirPrev == 1 && ArraySize(swLowLows) > 0)
        {
            ObjectDelete(0, "LW_DN");
            ObjectCreate(0, "LW_DN", OBJ_TREND, 0, hTime, ArrFirst(swHiHighs), ti, ArrFirst(swLowLows));
            ObjectSetInteger(0, "LW_DN", OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, "LW_DN", OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, "LW_DN", OBJPROP_RAY_RIGHT, true);

            ObjectSetDouble(0, "LW_UP", OBJPROP_PRICE, 1, ArrFirst(swHiHighs));
            ObjectSetInteger(0, "LW_UP", OBJPROP_TIME, 1, hTime);
        }

        //--- Extend up line
        if(swDir == 1 && swDirPrev == 1 && ArraySize(swHiHighs) > prevHiSize)
        {
            ObjectSetDouble(0, "LW_UP", OBJPROP_PRICE, 1, ArrFirst(swHiHighs));
            ObjectSetInteger(0, "LW_UP", OBJPROP_TIME, 1, ti);
        }

        //--- Extend down line
        if(swDir == -1 && swDirPrev == -1 && ArraySize(swLowHighs) > prevLowSize)
        {
            ObjectSetDouble(0, "LW_DN", OBJPROP_PRICE, 1, ArrFirst(swLowLows));
            ObjectSetInteger(0, "LW_DN", OBJPROP_TIME, 1, ti);
        }

        prevHiSize = ArraySize(swHiHighs);
        prevLowSize = ArraySize(swLowHighs);

        //--- Intermediate Trend Detector

        if(ArraySize(imTops) > 0 && imDir == 1 && swDir == -1 && swDirPrev == 1)
        {
            if(ArrFirst(swHiHighs) < ArrFirst(imTops))
            {
                imDir = -1;
                if(ShowIntermediateTrend)
                {
                    string lbl = "LW_DN_" + IntegerToString(ti);
                    ObjectCreate(0, lbl, OBJ_TEXT, 0, hTime, ArrFirst(swHiHighs));
                    ObjectSetString(0, lbl, OBJPROP_TEXT, "v");
                    ObjectSetInteger(0, lbl, OBJPROP_COLOR, clrCrimson);
                    ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 10);
                    ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_TOP);
                }
            }
        }

        if(ArraySize(imBots) > 0 && imDir == -1 && swDir == 1 && swDirPrev == -1)
        {
            if(ArrFirst(swLowLows) > ArrFirst(imBots))
            {
                imDir = 1;
                if(ShowIntermediateTrend)
                {
                    string lbl = "LW_UP_" + IntegerToString(ti);
                    ObjectCreate(0, lbl, OBJ_TEXT, 0, lTime, ArrFirst(swLowLows));
                    ObjectSetString(0, lbl, OBJPROP_TEXT, "^");
                    ObjectSetInteger(0, lbl, OBJPROP_COLOR, clrLimeGreen);
                    ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 10);
                    ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
                }
            }
        }

        if(swDir == 1 && swDirPrev == -1 && ArraySize(swLowLows) > 0)
            ArrUnshift(imBots, ArrFirst(swLowLows));

        if(swDir == -1 && swDirPrev == 1 && ArraySize(swHiHighs) > 0)
            ArrUnshift(imTops, ArrFirst(swHiHighs));
    }

    return rates_total;
}
//+------------------------------------------------------------------+
