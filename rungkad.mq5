//+------------------------------------------------------------------+
//|                   Aggressive Scalper EA v4.1                     |
//|         Zero Loss Buffer + Fibo Confluence + Hedging Recovery    |
//|                           FINAL VERSION - FIXED                  |
//+------------------------------------------------------------------+
#property copyright "Optimized for Zero Loss Scalping"
#property version   "4.11"
#property strict

// ============ INPUT PARAMETERS ============
input group "=== Trading Strategy ==="
input bool EnableSwingTrading = true;
input bool EnablePatternTrading = true;
input bool EnableSNRTrading = true;
input bool EnableTrendTrading = true;
input bool EnableFiboConfluence = true;
input int SwingLookback = 15;
input int SNRLookback = 50;
input int TrendPeriod = 50;

input group "=== Multi-Layer Entry Settings ==="
input bool EnableMultiLayerEntry = true;
input int MaxLayersPerSignal = 2;
input double LayerSpacing = 25;
input double LayerLotMultiplier = 1.0;

input group "=== Pattern Settings ==="
input bool UsePatternConfluence = true;
input double PatternStrengthThreshold = 3.0;

input group "=== SNR Settings ==="
input bool UseStaticSNR = true;
input bool UseDynamicSNR = true;
input bool UseVolatilityFilter = true;
input double VolatilityMultiplier = 1.5;

input group "=== Scalping Settings ==="
input ENUM_TIMEFRAMES ScalpingTimeframe = PERIOD_M1;
input int MaxOpenTrades = 8;
input double BaseLotSize = 0.01;
input bool UseAutoLotSize = true;
input double RiskPercent = 1.5;

input group "=== Risk Management ==="
input int StopLossPips = 100;
input int TakeProfitPips = 40;
input int TakeProfitPips2 = 250;
input int BreakevenBufferPips = 5;
input int TrailingStartPips = 50;
input int TrailingStopPips = 80;

input group "=== Hedging Recovery ==="
input bool EnableHedging = true;
input int HedgeThresholdPips = 50;
input int HedgeMagicNumber = 888889;

input group "=== Advanced ==="
input int MagicNumber = 888888;
input int Slippage = 30;
input bool ShowDebug = true;
input bool ShowPatternInfo = true;

// ============ ENUMS ============
enum CANDLE_PATTERN
{
   PATTERN_NONE = 0,
   PATTERN_BULLISH_ENGULFING = 1,
   PATTERN_BEARISH_ENGULFING = 2,
   PATTERN_HAMMER = 3,
   PATTERN_HANGING_MAN = 4,
   PATTERN_MORNING_STAR = 5,
   PATTERN_EVENING_STAR = 6,
   PATTERN_THREE_WHITE_SOLDIERS = 7,
   PATTERN_THREE_BLACK_CROWS = 8,
   PATTERN_SHOOTING_STAR = 9,
   PATTERN_INVERTED_HAMMER = 10,
   PATTERN_DOJI = 11,
   PATTERN_HARAMI_BULL = 12,
   PATTERN_HARAMI_BEAR = 13,
   PATTERN_PIERCING_LINE = 14,
   PATTERN_DARK_CLOUD_COVER = 15
};

struct SNRLevel
{
   double level;
   int touches;
   bool isResistance;
   double strength;
};

// ============ GLOBAL VARIABLES ============
SNRLevel snrLevels[];
double dailyProfit = 0;
double dailyLoss = 0;
datetime lastCheckDate = 0;
double lastLotSize = 0;
bool dailyTargetReached = false;
datetime lastDebugPrint = 0;

//+------------------------------------------------------------------+
//| Expert Initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("AGGRESSIVE SCALPER EA v4.1 INITIALIZED");
   Print("Multi-Layer Entry: ", EnableMultiLayerEntry ? "ON" : "OFF");
   Print("Pattern Trading: ", EnablePatternTrading ? "ON" : "OFF");
   Print("Hedging Recovery: ", EnableHedging ? "ON" : "OFF");
   Print("Max Layers: ", MaxLayersPerSignal);
   Print("Layer Spacing: ", LayerSpacing, " pips");
   Print("TP1 (Breakeven Trigger): ", TakeProfitPips, " pips");
   Print("========================================");
   
   ArrayResize(snrLevels, 0);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA Stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Main Tick Function                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDailyStats();
   
   if(dailyTargetReached)
   {
      UpdateDisplay();
      return;
   }
   
   if(EnableSNRTrading)
      UpdateSNRLevels();
   
   ManageOpenPositions();
   
   if(EnableHedging)
      ManageHedging();
      
   if(CountOpenTrades() >= MaxOpenTrades)
   {
      UpdateDisplay();
      return;
   }
   
   // Trading Logic
   if(EnableSwingTrading)
      CheckSwingTrade();
   if(EnablePatternTrading)
      CheckPatternTrade();
   if(EnableSNRTrading)
      CheckSNRTrade();
   if(EnableTrendTrading)
      CheckTrendTrade();
   
   UpdateDisplay();
}

//+------------------------------------------------------------------+
//| CHECK SWING TRADE                                                 |
//+------------------------------------------------------------------+
void CheckSwingTrade()
{
   double swingHigh = FindSwingHigh(SwingLookback);
   double swingLow = FindSwingLow(SwingLookback);
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double tolerance = 15 * GetPipValue();
   
   // BUY at Swing Low
   if(currentPrice <= swingLow + tolerance && currentPrice >= swingLow - tolerance)
   {
      double strength = CalculateSignalStrength(ORDER_TYPE_BUY, swingLow);
      if(strength >= PatternStrengthThreshold)
      {
         ExecuteMultiLayerEntry(ORDER_TYPE_BUY, ask, swingLow, "Swing Low Buy", strength);
      }
   }
   
   // SELL at Swing High
   if(currentPrice >= swingHigh - tolerance && currentPrice <= swingHigh + tolerance)
   {
      double strength = CalculateSignalStrength(ORDER_TYPE_SELL, swingHigh);
      if(strength >= PatternStrengthThreshold)
      {
         ExecuteMultiLayerEntry(ORDER_TYPE_SELL, currentPrice, swingHigh, "Swing High Sell", strength);
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK PATTERN TRADE                                               |
//+------------------------------------------------------------------+
void CheckPatternTrade()
{
   CANDLE_PATTERN bullishPattern = DetectBullishPattern();
   CANDLE_PATTERN bearishPattern = DetectBearishPattern();
   
   if(bullishPattern != PATTERN_NONE)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double low = iLow(_Symbol, ScalpingTimeframe, 0);
      double strength = CalculatePatternStrength(bullishPattern, true);
      if(strength >= PatternStrengthThreshold)
      {
         ExecuteMultiLayerEntry(ORDER_TYPE_BUY, ask, low, 
                                "Pattern: " + PatternToString(bullishPattern), strength);
      }
   }
   
   if(bearishPattern != PATTERN_NONE)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double high = iHigh(_Symbol, ScalpingTimeframe, 0);
      double strength = CalculatePatternStrength(bearishPattern, false);
      if(strength >= PatternStrengthThreshold)
      {
         ExecuteMultiLayerEntry(ORDER_TYPE_SELL, bid, high, 
                                "Pattern: " + PatternToString(bearishPattern), strength);
      }
   }
}

//+------------------------------------------------------------------+
//| DETECT BULLISH PATTERNS                                           |
//+------------------------------------------------------------------+
CANDLE_PATTERN DetectBullishPattern()
{
   double o0 = iOpen(_Symbol, ScalpingTimeframe, 0);
   double c0 = iClose(_Symbol, ScalpingTimeframe, 0);
   double h0 = iHigh(_Symbol, ScalpingTimeframe, 0);
   double l0 = iLow(_Symbol, ScalpingTimeframe, 0);
   
   double o1 = iOpen(_Symbol, ScalpingTimeframe, 1);
   double c1 = iClose(_Symbol, ScalpingTimeframe, 1);
   double l1 = iLow(_Symbol, ScalpingTimeframe, 1);
   
   double o2 = iOpen(_Symbol, ScalpingTimeframe, 2);
   double c2 = iClose(_Symbol, ScalpingTimeframe, 2);
   double l2 = iLow(_Symbol, ScalpingTimeframe, 2);
   
   // Bullish Engulfing
   if(c2 > o2 && c1 < o1 && c0 > o0 && c0 > o1 && o0 < c1)
      return PATTERN_BULLISH_ENGULFING;
   
   double bodySize = MathAbs(c0 - o0);
   double lowerWick = MathMin(o0, c0) - l0;
   double upperWick = h0 - MathMax(o0, c0);
   
   // Hammer
   if(bodySize > 0 && lowerWick > bodySize * 2 && upperWick < bodySize)
      return PATTERN_HAMMER;
   
   // Inverted Hammer
   if(bodySize > 0 && upperWick > bodySize * 2 && lowerWick < bodySize)
      return PATTERN_INVERTED_HAMMER;
   
   // Morning Star
   if(c2 < o2 && c1 < o1 && bodySize < MathAbs(c2 - o2) * 0.5 && c0 > o0)
      return PATTERN_MORNING_STAR;
   
   // Harami Bull
   if(c2 < o2 && c0 > o0 && o0 > l2 && c0 < h0 && MathAbs(c0 - o0) < MathAbs(c2 - o2) * 0.5)
      return PATTERN_HARAMI_BULL;
   
   // Piercing Line
   if(c2 < o2 && c1 < l2 && c0 > o0 && c0 > ((o2 + c2) / 2) && o0 < c2)
      return PATTERN_PIERCING_LINE;
   
   // Three White Soldiers
   if(c2 > o2 && c1 > o1 && c0 > o0 && c1 > c2 && c0 > c1)
      return PATTERN_THREE_WHITE_SOLDIERS;
   
   // Doji
   if(MathAbs(c0 - o0) < bodySize * 0.1 && (h0 - l0) > bodySize * 3)
      return PATTERN_DOJI;
   
   return PATTERN_NONE;
}

//+------------------------------------------------------------------+
//| DETECT BEARISH PATTERNS                                           |
//+------------------------------------------------------------------+
CANDLE_PATTERN DetectBearishPattern()
{
   double o0 = iOpen(_Symbol, ScalpingTimeframe, 0);
   double c0 = iClose(_Symbol, ScalpingTimeframe, 0);
   double h0 = iHigh(_Symbol, ScalpingTimeframe, 0);
   double l0 = iLow(_Symbol, ScalpingTimeframe, 0);
   
   double o1 = iOpen(_Symbol, ScalpingTimeframe, 1);
   double c1 = iClose(_Symbol, ScalpingTimeframe, 1);
   double h1 = iHigh(_Symbol, ScalpingTimeframe, 1);
   
   double o2 = iOpen(_Symbol, ScalpingTimeframe, 2);
   double c2 = iClose(_Symbol, ScalpingTimeframe, 2);
   double h2 = iHigh(_Symbol, ScalpingTimeframe, 2);
   
   // Bearish Engulfing
   if(c2 < o2 && c1 > o1 && c0 < o0 && c0 < o1 && o0 > c1)
      return PATTERN_BEARISH_ENGULFING;
   
   double bodySize = MathAbs(c0 - o0);
   double lowerWick = MathMin(o0, c0) - l0;
   double upperWick = h0 - MathMax(o0, c0);
   
   // Hanging Man
   if(bodySize > 0 && lowerWick > bodySize * 2 && upperWick < bodySize)
      return PATTERN_HANGING_MAN;
   
   // Shooting Star
   if(bodySize > 0 && upperWick > bodySize * 2 && lowerWick < bodySize)
      return PATTERN_SHOOTING_STAR;
   
   // Evening Star
   if(c2 > o2 && c1 > o1 && bodySize < MathAbs(c2 - o2) * 0.5 && c0 < o0)
      return PATTERN_EVENING_STAR;
   
   // Harami Bear
   if(c2 > o2 && c0 < o0 && o0 < h2 && c0 > l0 && MathAbs(c0 - o0) < MathAbs(c2 - o2) * 0.5)
      return PATTERN_HARAMI_BEAR;
   
   // Dark Cloud Cover
   if(c2 > o2 && c1 > o1 && c0 < o0 && o0 > h2 && c0 < ((o2 + c2) / 2))
      return PATTERN_DARK_CLOUD_COVER;
   
   // Three Black Crows
   if(c2 < o2 && c1 < o1 && c0 < o0 && c1 < c2 && c0 < c1)
      return PATTERN_THREE_BLACK_CROWS;
   
   // Doji
   if(MathAbs(c0 - o0) < bodySize * 0.1 && (h0 - l0) > bodySize * 3)
      return PATTERN_DOJI;
   
   return PATTERN_NONE;
}

//+------------------------------------------------------------------+
//| CALCULATE PATTERN STRENGTH                                        |
//+------------------------------------------------------------------+
double CalculatePatternStrength(CANDLE_PATTERN pattern, bool isBullish)
{
   double strength = 0;
   
   switch(pattern)
   {
      case PATTERN_BULLISH_ENGULFING:
      case PATTERN_BEARISH_ENGULFING: 
         strength = 3.0; 
         break;
      case PATTERN_MORNING_STAR:
      case PATTERN_EVENING_STAR: 
         strength = 2.8; 
         break;
      case PATTERN_THREE_WHITE_SOLDIERS:
      case PATTERN_THREE_BLACK_CROWS: 
         strength = 2.6; 
         break;
      case PATTERN_HAMMER:
      case PATTERN_SHOOTING_STAR: 
         strength = 2.4; 
         break;
      case PATTERN_HARAMI_BULL:
      case PATTERN_HARAMI_BEAR: 
         strength = 2.2; 
         break;
      case PATTERN_PIERCING_LINE:
      case PATTERN_DARK_CLOUD_COVER: 
         strength = 2.1; 
         break;
      case PATTERN_DOJI: 
         strength = 1.8; 
         break;
      default: 
         strength = 1.0;
   }
   
   if(UsePatternConfluence)
   {
      if(EnableSNRTrading && IsNearSNRLevel(isBullish, 15))
         strength += 0.5;
         
      if(EnableFiboConfluence && IsNearFiboLevel(isBullish, 15))
         strength += 0.6;

      if(IsWithTrend(isBullish))
         strength += 0.4;
         
      if(HasIncreasingVolume())
         strength += 0.3;
   }
   
   return strength;
}

//+------------------------------------------------------------------+
//| PATTERN TO STRING                                                 |
//+------------------------------------------------------------------+
string PatternToString(CANDLE_PATTERN pattern)
{
   switch(pattern)
   {
      case PATTERN_BULLISH_ENGULFING: return "Bullish Engulfing";
      case PATTERN_BEARISH_ENGULFING: return "Bearish Engulfing";
      case PATTERN_HAMMER: return "Hammer";
      case PATTERN_HANGING_MAN: return "Hanging Man";
      case PATTERN_MORNING_STAR: return "Morning Star";
      case PATTERN_EVENING_STAR: return "Evening Star";
      case PATTERN_THREE_WHITE_SOLDIERS: return "Three White Soldiers";
      case PATTERN_THREE_BLACK_CROWS: return "Three Black Crows";
      case PATTERN_SHOOTING_STAR: return "Shooting Star";
      case PATTERN_INVERTED_HAMMER: return "Inverted Hammer";
      case PATTERN_DOJI: return "Doji";
      case PATTERN_HARAMI_BULL: return "Harami Bull";
      case PATTERN_HARAMI_BEAR: return "Harami Bear";
      case PATTERN_PIERCING_LINE: return "Piercing Line";
      case PATTERN_DARK_CLOUD_COVER: return "Dark Cloud Cover";
      default: return "Unknown Pattern";
   }
}

//+------------------------------------------------------------------+
//| UPDATE SNR LEVELS                                                 |
//+------------------------------------------------------------------+
void UpdateSNRLevels()
{
   ArrayResize(snrLevels, 0);
   
   double high[];
   double low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   int copySize = SNRLookback;
   if(CopyHigh(_Symbol, ScalpingTimeframe, 0, copySize, high) <= 0)
      return;
   if(CopyLow(_Symbol, ScalpingTimeframe, 0, copySize, low) <= 0)
      return;
   
   if(UseStaticSNR)
   {
      double maxHigh = high[ArrayMaximum(high, 0, copySize)];
      double minLow = low[ArrayMinimum(low, 0, copySize)];
      
      SNRLevel resistance = {};
      resistance.level = maxHigh;
      resistance.isResistance = true;
      resistance.strength = 1.0;
      ArrayResize(snrLevels, ArraySize(snrLevels) + 1);
      snrLevels[ArraySize(snrLevels) - 1] = resistance;
      
      SNRLevel support = {};
      support.level = minLow;
      support.isResistance = false;
      support.strength = 1.0;
      ArrayResize(snrLevels, ArraySize(snrLevels) + 1);
      snrLevels[ArraySize(snrLevels) - 1] = support;
   }
   
   if(UseDynamicSNR)
   {
      double swingHigh = FindSwingHigh(SwingLookback);
      SNRLevel sh = {};
      sh.level = swingHigh;
      sh.isResistance = true;
      sh.strength = 1.5;
      ArrayResize(snrLevels, ArraySize(snrLevels) + 1);
      snrLevels[ArraySize(snrLevels) - 1] = sh;
      
      double swingLow = FindSwingLow(SwingLookback);
      SNRLevel sl = {};
      sl.level = swingLow;
      sl.isResistance = false;
      sl.strength = 1.5;
      ArrayResize(snrLevels, ArraySize(snrLevels) + 1);
      snrLevels[ArraySize(snrLevels) - 1] = sl;
   }
}

//+------------------------------------------------------------------+
//| CHECK SNR TRADE                                                   |
//+------------------------------------------------------------------+
void CheckSNRTrade()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   for(int i = 0; i < ArraySize(snrLevels); i++)
   {
      double tolerance = 20 * GetPipValue();
      double distance = MathAbs(currentPrice - snrLevels[i].level);
      
      if(distance <= tolerance)
      {
         if(snrLevels[i].isResistance)
         {
            if(!HasOpenNearSNR(POSITION_TYPE_SELL, snrLevels[i].level, 30))
            {
               ExecuteMultiLayerEntry(ORDER_TYPE_SELL, currentPrice, 
                                       snrLevels[i].level,
                                       "Resistance Level", 
                                       snrLevels[i].strength);
            }
         }
         else
         {
            if(!HasOpenNearSNR(POSITION_TYPE_BUY, snrLevels[i].level, 30))
            {
               ExecuteMultiLayerEntry(ORDER_TYPE_BUY, ask, 
                                       snrLevels[i].level,
                                       "Support Level", 
                                       snrLevels[i].strength);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| EXECUTE MULTI-LAYER ENTRY                                         |
//+------------------------------------------------------------------+
void ExecuteMultiLayerEntry(ENUM_ORDER_TYPE orderType, double price, 
                             double baseLevel, string comment, double strength)
{
   if(!EnableMultiLayerEntry)
   {
      double sl = (orderType == ORDER_TYPE_BUY) ?
         baseLevel - (StopLossPips * GetPipValue()) :
         baseLevel + (StopLossPips * GetPipValue());
      double tp = (orderType == ORDER_TYPE_BUY) ?
         price + (TakeProfitPips * GetPipValue()) :
         price - (TakeProfitPips * GetPipValue());
      OpenTrade(orderType, price, sl, tp, comment);
      return;
   }
   
   int layersToOpen = (int)(strength / PatternStrengthThreshold);
   if(layersToOpen > MaxLayersPerSignal)
      layersToOpen = MaxLayersPerSignal;
   if(layersToOpen < 1)
      layersToOpen = 1;
   
   double currentEntryPrice = price;
   
   double slForLotCalc = (orderType == ORDER_TYPE_BUY) ?
      baseLevel - (StopLossPips * GetPipValue()) :
      baseLevel + (StopLossPips * GetPipValue());
      
   double baseLot = CalculateLotSize(slForLotCalc, price);

   for(int layer = 0; layer < layersToOpen; layer++)
   {
      double entryPrice = currentEntryPrice;
      
      if(layer > 0)
      {
         double spacing = LayerSpacing * GetPipValue();
         entryPrice = (orderType == ORDER_TYPE_BUY) ?
                      currentEntryPrice - (spacing * layer) :
                      currentEntryPrice + (spacing * layer);
      }
      
      double layerLot = baseLot * MathPow(LayerLotMultiplier, (double)layer);
      
      double sl = (orderType == ORDER_TYPE_BUY) ?
                  baseLevel - (StopLossPips * GetPipValue()) :
                  baseLevel + (StopLossPips * GetPipValue());
      double tp = (orderType == ORDER_TYPE_BUY) ?
                  entryPrice + (TakeProfitPips * GetPipValue()) :
                  entryPrice - (TakeProfitPips * GetPipValue());

      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.volume = NormalizeDouble(layerLot, 2);
      request.type = orderType;
      request.price = NormalizeDouble(entryPrice, _Digits);
      request.sl = NormalizeDouble(sl, _Digits);
      request.tp = NormalizeDouble(tp, _Digits);
      request.deviation = Slippage;
      request.magic = MagicNumber;
      request.comment = comment + " [Layer " + IntegerToString(layer + 1) + "]";
      request.type_filling = ORDER_FILLING_FOK;
      
      if(!OrderSend(request, result))
      {
         request.type_filling = ORDER_FILLING_IOC;
         OrderSend(request, result);
      }
      
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("✅ Layer ", layer + 1, " opened: ", request.comment,
               " | Lot: ", DoubleToString(layerLot, 2),
               " | Price: ", DoubleToString(entryPrice, _Digits));
      }
      
      Sleep(100);
   }
}

//+------------------------------------------------------------------+
//| IS NEAR SNR LEVEL                                                 |
//+------------------------------------------------------------------+
bool IsNearSNRLevel(bool isBullish, int pipsDistance)
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double distance = pipsDistance * GetPipValue();
   
   for(int i = 0; i < ArraySize(snrLevels); i++)
   {
      if(isBullish && !snrLevels[i].isResistance)
      {
         if(MathAbs(currentPrice - snrLevels[i].level) <= distance)
            return true;
      }
      else if(!isBullish && snrLevels[i].isResistance)
      {
         if(MathAbs(currentPrice - snrLevels[i].level) <= distance)
            return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| HAS OPEN NEAR SNR                                                 |
//+------------------------------------------------------------------+
bool HasOpenNearSNR(ENUM_POSITION_TYPE posType, double snrLevel, int pipDistance)
{
   double distance = pipDistance * GetPipValue();
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetInteger(POSITION_TYPE) == posType)
      {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         if(MathAbs(openPrice - snrLevel) <= distance)
            return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| IS WITH TREND                                                     |
//+------------------------------------------------------------------+
bool IsWithTrend(bool isBullish)
{
   double ma[];
   ArraySetAsSeries(ma, true);
   
   int maHandle = iMA(_Symbol, ScalpingTimeframe, TrendPeriod, 0, 
                      MODE_EMA, PRICE_CLOSE);
   if(CopyBuffer(maHandle, 0, 0, 2, ma) <= 0)
      return false;
   
   double currentPrice = iClose(_Symbol, ScalpingTimeframe, 0);
   if(isBullish)
      return (currentPrice > ma[0] && ma[0] > ma[1]);
   else
      return (currentPrice < ma[0] && ma[0] < ma[1]);
}

//+------------------------------------------------------------------+
//| HAS INCREASING VOLUME                                             |
//+------------------------------------------------------------------+
bool HasIncreasingVolume()
{
   long vol0 = iVolume(_Symbol, ScalpingTimeframe, 0);
   long vol1 = iVolume(_Symbol, ScalpingTimeframe, 1);
   
   return (vol0 > vol1);
}

//+------------------------------------------------------------------+
//| CALCULATE SIGNAL STRENGTH                                         |
//+------------------------------------------------------------------+
double CalculateSignalStrength(ENUM_ORDER_TYPE type, double level)
{
   double strength = 1.0;
   bool isBullish = (type == ORDER_TYPE_BUY);
   
   if(IsWithTrend(isBullish))
      strength += 0.5;
   
   if(IsNearSNRLevel(isBullish, 20))
      strength += 0.3;
      
   if(EnableFiboConfluence && IsNearFiboLevel(isBullish, 15))
      strength += 0.6;
      
   if(HasIncreasingVolume())
      strength += 0.2;
   
   return strength;
}

//+------------------------------------------------------------------+
//| FIND SWING HIGH                                                   |
//+------------------------------------------------------------------+
double FindSwingHigh(int lookback)
{
   if(lookback < 3) lookback = 3;
   
   double high[];
   ArraySetAsSeries(high, true);
   int copySize = lookback + 5;
   if(CopyHigh(_Symbol, ScalpingTimeframe, 0, copySize, high) <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double swingHigh = high[0];
   
   for(int i = 1; i < copySize - 1; i++)
   {
      if(high[i] > high[i-1] && high[i] >= high[i+1] && high[i] > swingHigh)
         swingHigh = high[i];
   }
   
   return swingHigh;
}

//+------------------------------------------------------------------+
//| FIND SWING LOW                                                    |
//+------------------------------------------------------------------+
double FindSwingLow(int lookback)
{
   if(lookback < 3) lookback = 3;
   
   double low[];
   ArraySetAsSeries(low, true);
   int copySize = lookback + 5;
   if(CopyLow(_Symbol, ScalpingTimeframe, 0, copySize, low) <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double swingLow = low[0];
   
   for(int i = 1; i < copySize - 1; i++)
   {
      if(low[i] < low[i-1] && low[i] <= low[i+1] && low[i] < swingLow)
         swingLow = low[i];
   }
   
   return swingLow;
}

//+------------------------------------------------------------------+
//| OPEN TRADE                                                        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType, double price, double sl, double tp, 
               string comment)
{
   double lots = CalculateLotSize(sl, price);
   
   if(lots <= 0)
      return;
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = orderType;
   request.price = NormalizeDouble(price, _Digits);
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   request.deviation = Slippage;
   request.magic = MagicNumber;
   request.comment = comment;
   request.type_filling = ORDER_FILLING_FOK;
   
   if(!OrderSend(request, result))
   {
      request.type_filling = ORDER_FILLING_IOC;
      OrderSend(request, result);
   }
   
   if(result.retcode == TRADE_RETCODE_DONE)
   {
      Print("✅ Trade opened: ", comment, " | Lot: ", DoubleToString(lots, 2),
            " | Price: ", DoubleToString(price, _Digits));
   }
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl, double entryPrice)
{
   double lots = BaseLotSize;
   
   if(UseAutoLotSize)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      if(balance <= 0)
         return BaseLotSize;
      
      double riskAmount = balance * (RiskPercent / 100.0);
      double slDistance = MathAbs(entryPrice - sl);
      
      if(slDistance <= 0)
         return BaseLotSize;
      
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      
      if(tickSize <= 0 || tickValue <= 0)
         return BaseLotSize;
      
      double divisor = (slDistance / tickSize) * tickValue;
      
      if(divisor <= 0)
         return BaseLotSize;
      
      lots = riskAmount / divisor;
   }
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(minLot <= 0 || maxLot <= 0 || lotStep <= 0)
      return BaseLotSize;
   
   lots = MathMax(minLot, MathMin(maxLot, NormalizeDouble(lots / lotStep, 0) * lotStep));
   
   return lots;
}

//+------------------------------------------------------------------+
//| MANAGE OPEN POSITIONS                                             |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentVolume = PositionGetDouble(POSITION_VOLUME);
      
      double currentPrice = (posType == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profitPips = (posType == POSITION_TYPE_BUY) ?
                          (currentPrice - openPrice) / GetPipValue() :
                          (openPrice - currentPrice) / GetPipValue();
      
      // Partial Close (TP1) and Breakeven
      if(profitPips >= TakeProfitPips)
      {
         double closeVolume = NormalizeDouble(currentVolume / 2.0, 2);
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

         if(closeVolume >= minLot && ClosePartialPosition(ticket, closeVolume))
         {
            double breakevenBuffer = BreakevenBufferPips * GetPipValue();
            double newSL = (posType == POSITION_TYPE_BUY) ?
                           openPrice + breakevenBuffer :
                           openPrice - breakevenBuffer;
                           
            double tp2Distance = TakeProfitPips2 * GetPipValue();
            double newTP = (posType == POSITION_TYPE_BUY) ?
                           openPrice + tp2Distance :
                           openPrice - tp2Distance;

            ModifyPosition(ticket, newSL, newTP);
            Print("✅ TP1 Hit! Partial close executed. Breakeven set.");
         }
      }
      
      // Trailing Stop
      if(profitPips >= TrailingStartPips)
      {
         double newSL = (posType == POSITION_TYPE_BUY) ?
                        currentPrice - (TrailingStopPips * GetPipValue()) :
                        currentPrice + (TrailingStopPips * GetPipValue());
         
         if((posType == POSITION_TYPE_BUY && newSL > currentSL) ||
            (posType == POSITION_TYPE_SELL && newSL < currentSL))
         {
            ModifyPosition(ticket, newSL, currentTP);
            Print("🔄 Trailing Stop updated for ticket: ", ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MODIFY POSITION                                                   |
//+------------------------------------------------------------------+
bool ModifyPosition(ulong ticket, double sl, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   
   if(!OrderSend(request, result))
      return false;
   
   return (result.retcode == TRADE_RETCODE_DONE);
}

//+------------------------------------------------------------------+
//| COUNT OPEN TRADES                                                 |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| CHECK TREND TRADE                                                 |
//+------------------------------------------------------------------+
void CheckTrendTrade()
{
   double ma[];
   ArraySetAsSeries(ma, true);
   
   int maHandle = iMA(_Symbol, ScalpingTimeframe, TrendPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(CopyBuffer(maHandle, 0, 0, 3, ma) <= 0)
      return;
   
   double currentPrice = iClose(_Symbol, ScalpingTimeframe, 0);
   
   if(currentPrice > ma[0] && ma[0] > ma[1])
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      ExecuteMultiLayerEntry(ORDER_TYPE_BUY, ask, ma[0], "Trend Buy", 1.5);
   }
   
   if(currentPrice < ma[0] && ma[0] < ma[1])
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      ExecuteMultiLayerEntry(ORDER_TYPE_SELL, bid, ma[0], "Trend Sell", 1.5);
   }
}

//+------------------------------------------------------------------+
//| UPDATE DAILY STATS                                                |
//+------------------------------------------------------------------+
void UpdateDailyStats()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today != lastCheckDate)
   {
      dailyProfit = 0;
      dailyLoss = 0;
      dailyTargetReached = false;
      lastCheckDate = today;
   }
   
   double totalProfit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            totalProfit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double profitPercent = (balance > 0) ? (totalProfit / balance) * 100 : 0;
   
   if(profitPercent > 0)
      dailyProfit = profitPercent;
   else
      dailyLoss = MathAbs(profitPercent);
}

//+------------------------------------------------------------------+
//| GET PIP VALUE                                                     |
//+------------------------------------------------------------------+
double GetPipValue()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (digits == 3 || digits == 5) ? point * 10 : point;
}

//+------------------------------------------------------------------+
//| FIND FIBO LEVEL                                                   |
//+------------------------------------------------------------------+
double FindFiboLevel(int lookback, double level)
{
    double high = FindSwingHigh(lookback);
    double low = FindSwingLow(lookback);
    
    if(MathAbs(high - low) < 0.0001)
       return 0.0;
    
    return high - ((high - low) * level);
}

//+------------------------------------------------------------------+
//| IS NEAR FIBO LEVEL                                                |
//+------------------------------------------------------------------+
bool IsNearFiboLevel(bool isBullish, int pipsDistance)
{
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double distance = pipsDistance * GetPipValue();
    
    double fibo618 = FindFiboLevel(SwingLookback, 0.618);
    double fibo50 = FindFiboLevel(SwingLookback, 0.50);

    if(fibo618 > 0 && MathAbs(currentPrice - fibo618) <= distance) 
       return true;
    if(fibo50 > 0 && MathAbs(currentPrice - fibo50) <= distance) 
       return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| GET TOTAL LOTS                                                    |
//+------------------------------------------------------------------+
double GetTotalLots(int magicNumber, ENUM_POSITION_TYPE type)
{
   double totalLot = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) == magicNumber && 
         PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(posType == type)
            totalLot += PositionGetDouble(POSITION_VOLUME);
      }
   }
   return totalLot;
}

//+------------------------------------------------------------------+
//| OPEN HEDGE TRADE                                                  |
//+------------------------------------------------------------------+
bool OpenHedgeTrade(ENUM_ORDER_TYPE orderType, double lots, string comment)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = NormalizeDouble(lots, 2);
   request.type = orderType;
   request.price = (orderType == ORDER_TYPE_BUY) ? 
                   SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                   SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = 0.0;
   request.tp = 0.0;
   request.deviation = Slippage;
   request.magic = HedgeMagicNumber;
   request.comment = comment;
   request.type_filling = ORDER_FILLING_IOC;
   
   bool success = OrderSend(request, result);
   
   if(success && result.retcode == TRADE_RETCODE_DONE)
   {
      Print("✅ Hedge position opened: ", comment, " | Lot: ", DoubleToString(lots, 2));
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| HAS HEDGE POSITION OPEN                                           |
//+------------------------------------------------------------------+
bool HasHedgePositionOpen()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) == HedgeMagicNumber && 
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| MANAGE HEDGING                                                    |
//+------------------------------------------------------------------+
void ManageHedging()
{
   if(!EnableHedging) 
      return;
   
   double totalFloatingProfit = 0;
   int mainPositions = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
         PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         totalFloatingProfit += PositionGetDouble(POSITION_PROFIT);
         mainPositions++;
      }
   }
   
   double totalLots = GetTotalLots(MagicNumber, POSITION_TYPE_BUY) + 
                      GetTotalLots(MagicNumber, POSITION_TYPE_SELL);
   
   double hedgeThresholdValue = HedgeThresholdPips * GetPipValue() * totalLots;
   
   if(totalFloatingProfit < -hedgeThresholdValue && mainPositions >= 2)
   {
      if(!HasHedgePositionOpen())
      {
         double buyLots = GetTotalLots(MagicNumber, POSITION_TYPE_BUY);
         double sellLots = GetTotalLots(MagicNumber, POSITION_TYPE_SELL);
         
         ENUM_ORDER_TYPE hedgeType = (buyLots >= sellLots) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         
         if(totalLots > 0)
         {
            OpenHedgeTrade(hedgeType, totalLots, "HEDGE ACTIVATED");
         }
      }
   }
   
   if(HasHedgePositionOpen())
   {
      if(totalFloatingProfit >= -hedgeThresholdValue * 0.5)
      {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            if(PositionGetInteger(POSITION_MAGIC) == HedgeMagicNumber && 
               PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
               ClosePartialPosition(ticket, PositionGetDouble(POSITION_VOLUME));
               Print("✅ HEDGE CLOSED: Recovery activated.");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CLOSE PARTIAL POSITION                                            |
//+------------------------------------------------------------------+
bool ClosePartialPosition(ulong ticket, double closeVolume)
{
   if(!PositionSelectByTicket(ticket))
   {
      Print("❌ ClosePartialPosition: Ticket not found: ", ticket);
      return false;
   }
   
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = PositionGetString(POSITION_SYMBOL);
   request.volume = NormalizeDouble(closeVolume, 2);
   request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = (request.type == ORDER_TYPE_SELL) ? 
                   SymbolInfoDouble(request.symbol, SYMBOL_BID) : 
                   SymbolInfoDouble(request.symbol, SYMBOL_ASK);
   request.deviation = Slippage;
   request.magic = (int)PositionGetInteger(POSITION_MAGIC);
   request.type_filling = ORDER_FILLING_RETURN;
   
   bool success = OrderSend(request, result);

   if(success && result.retcode == TRADE_RETCODE_DONE)
   {
       Print("✅ Partial Close success. Ticket: ", ticket, " Volume: ", DoubleToString(closeVolume, 2));
       return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| UPDATE DISPLAY                                                    |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   if(ShowPatternInfo && TimeCurrent() - lastDebugPrint > 60)
   {
      CANDLE_PATTERN bullPattern = DetectBullishPattern();
      CANDLE_PATTERN bearPattern = DetectBearishPattern();
      
      if(bullPattern != PATTERN_NONE || bearPattern != PATTERN_NONE)
      {
         Print("\n=== PATTERN DETECTED ===");
         if(bullPattern != PATTERN_NONE)
            Print("📈 Bullish: ", PatternToString(bullPattern));
         if(bearPattern != PATTERN_NONE)
            Print("📉 Bearish: ", PatternToString(bearPattern));
         Print("========================\n");
      }
      
      lastDebugPrint = TimeCurrent();
   }
   
   string info = "\n========== AGGRESSIVE SCALPER EA v4.1 FIXED ==========\n";
   info += "Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\n";
   info += "Symbol: " + _Symbol + " | TF: " + EnumToString(ScalpingTimeframe) + "\n";
   info += "-------------------------------------------\n";
   info += "Account Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
   info += "Account Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
   info += "-------------------------------------------\n";
   info += "Open Trades: " + IntegerToString(CountOpenTrades()) + " / " + IntegerToString(MaxOpenTrades) + "\n";
   info += "Daily Profit: " + DoubleToString(dailyProfit, 2) + "%\n";
   info += "Daily Loss: " + DoubleToString(dailyLoss, 2) + "%\n";
   info += "-------------------------------------------\n";
   info += "Features Enabled:\n";
   info += "  Swing Trading: " + (EnableSwingTrading ? "✅" : "❌") + "\n";
   info += "  Pattern Trading: " + (EnablePatternTrading ? "✅" : "❌") + "\n";
   info += "  SNR Trading: " + (EnableSNRTrading ? "✅" : "❌") + "\n";
   info += "  Trend Trading: " + (EnableTrendTrading ? "✅" : "❌") + "\n";
   info += "  Fibo Confluence: " + (EnableFiboConfluence ? "✅" : "❌") + "\n";
   info += "  Hedging Recovery: " + (EnableHedging ? "✅" : "❌") + "\n";
   info += "  Multi-Layer Entry: " + (EnableMultiLayerEntry ? "✅" : "❌") + "\n";
   info += "-------------------------------------------\n";
   info += "SNR Levels Found: " + IntegerToString(ArraySize(snrLevels)) + "\n";
   info += "=================================================\n";
   
   Comment(info);
}
//+------------------------------------------------------------------+ 