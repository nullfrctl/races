#ifndef _ACES_LIB_RRT_COMMON
#define _ACES_LIB_RRT_COMMON

// <ACEStransformID>urn:ampas:aces:transformId:v1.5:ACESlib.RRT_Common.a1.1.0</ACEStransformID>
// <ACESuserName>ACES 1.0 Lib - RRT Common</ACESuserName>

//
// Contains functions and constants shared by forward and inverse RRT transforms
//

#include "CTLlib.hlsl"
#include "ACESlib.Utilities.hlsl"
#include "ACESlib.Utilities_Color.hlsl"
#include "ACESlib.Transform_Common.hlsl"

// "Glow" module constants
static const float RRT_GLOW_GAIN = 0.05;
static const float RRT_GLOW_MID = 0.08;

// Red modifier constants
static const float RRT_RED_SCALE = 0.82;
static const float RRT_RED_PIVOT = 0.03;
static const float RRT_RED_HUE = 0.;
static const float RRT_RED_WIDTH = 135.;

// Desaturation contants
static const float RRT_SAT_FACTOR = 0.96;
#ifndef __RESHADE__
static const float3x3 RRT_SAT_MAT = calc_sat_adjust_matrix( RRT_SAT_FACTOR, AP1_RGB2Y);// "Glow" module constants
#else
float3x3 _RRT_SAT_MAT()
{
  return calc_sat_adjust_matrix( RRT_SAT_FACTOR, AP1_RGB2Y);
}
#define RRT_SAT_MAT _RRT_SAT_MAT()
#endif

// ------- Glow module functions
float glow_fwd( float ycIn, float glowGainIn, float glowMid)
{
  float glowGainOut;

  if ( ycIn <= 2. / 3. * glowMid)
    glowGainOut = glowGainIn;
  else if ( ycIn >= 2. * glowMid)
    glowGainOut = 0.;
  else
    glowGainOut = glowGainIn * ( glowMid / ycIn - 0.5);

  return glowGainOut;
}

float glow_inv( float ycOut, float glowGainIn, float glowMid)
{
  float glowGainOut;

  if ( ycOut <= ( ( 1. + glowGainIn) * 2. / 3. * glowMid))
    glowGainOut = -glowGainIn / ( 1. + glowGainIn);
  else if ( ycOut >= ( 2. * glowMid))
    glowGainOut = 0.;
  else
    glowGainOut = glowGainIn * ( glowMid / ycOut - 0.5) / ( glowGainIn * 0.5 - 1.);
  
  return glowGainOut;
}

float sigmoid_shaper( float x)
{
  // Sigmoid function in the range 0 to 1 spanning -2 to +2.

  float t = max( 1. - fabs( x * 0.5), 0.);
  float y = 1. + sign( x) * ( 1. - t * t);

  return y * 0.5;
}

// ------- Red modifier functions
float cubic_basis_shaper
  ( float x,
    float w // full base width of the shaper function (in degrees)
  )
{
  float4x4 M = float4x4( -1. / 6,  3. / 6, -3. / 6,  1. / 6,
                          3. / 6, -6. / 6,  3. / 6,  0. / 6,
                         -3. / 6,  0. / 6,  3. / 6,  0. / 6,
                          1. / 6,  4. / 6,  1. / 6,  0. / 6 );

  float knots[5] = { -w * 0.5,
                     -w * 0.25,
                     0.,
                     w * 0.25,
                     w * 0.5 };

  float y = 0.;
  if ((x > knots[0]) && (x < knots[4])) {  
    float knot_coord = (x - knots[0]) * 4./w;  
    int j = knot_coord;
    float t = knot_coord - j;
      
    float monomials[4] = { t*t*t, t*t, t, 1. };

    // (if/else structure required for compatibility with CTL < v1.5.)
    if ( j == 3) {
      y = monomials[0] * M[0][0] + monomials[1] * M[1][0] + 
          monomials[2] * M[2][0] + monomials[3] * M[3][0];
    } else if ( j == 2) {
      y = monomials[0] * M[0][1] + monomials[1] * M[1][1] + 
          monomials[2] * M[2][1] + monomials[3] * M[3][1];
    } else if ( j == 1) {
      y = monomials[0] * M[0][2] + monomials[1] * M[1][2] + 
          monomials[2] * M[2][2] + monomials[3] * M[3][2];
    } else if ( j == 0) {
      y = monomials[0] * M[0][3] + monomials[1] * M[1][3] + 
          monomials[2] * M[2][3] + monomials[3] * M[3][3];
    } else {
      y = 0.0;
    }
  }

  return y * 3. / 2.;
}

float center_hue( float hue, float centerH)
{
  float hueCentered = hue - centerH;
  if (hueCentered < -180.) hueCentered += 360.;
  else if (hueCentered > 180.) hueCentered -= 360.;
  return hueCentered;
}

float uncenter_hue( float hueCentered, float centerH)
{
  float hue = hueCentered + centerH;
  if (hue < 0.) hue += 360.;
  else if (hue > 360.) hue += 360.;
  return hue;
}

float3 rrt_sweeteners( float3 _in)
{
  float3 aces = _in;

  // --- Glow module --- //
  float saturation = rgb_2_saturation( aces);
  float ycIn = rgb_2_yc( aces);
  float s = sigmoid_shaper( ( saturation - 0.4) * 0.5);
  float addedGlow = 1. + glow_fwd( ycIn, RRT_GLOW_GAIN * s, RRT_GLOW_MID);

  aces = mult_f_f3( addedGlow, aces);

  // --- Red modifier --- //
  float hue = rgb_2_hue( aces);
  float centeredHue = center_hue( hue, RRT_RED_HUE);
  float hueWeight = cubic_basis_shaper( centeredHue, RRT_RED_WIDTH);
  // float hueWeight = smoothstep( 0.0, 1.0, 1.0 - abs( 2.0 * centeredHue / RRT_RED_WIDTH));
  // hueWeight *= hueWeight;

  aces.r += hueWeight * saturation * ( RRT_RED_PIVOT - aces.r) * ( 1. - RRT_RED_SCALE);

  // --- ACES to RGB rendering space --- //
  aces = clamp_f3( aces, 0., 65504.);
  float3 rgbPre = mult_f3_f33( aces, AP0_2_AP1_MAT);
  rgbPre = clamp_f3( rgbPre, 0., 65504.);

  // --- Global desaturation --- //
  rgbPre = mult_f3_f33( rgbPre, RRT_SAT_MAT);

  return rgbPre;
}

float3 inv_rrt_sweeteners( float3 _in)
{
  float3 rgbPost = _in;

  // --- Global desaturation --- //
  rgbPost = mult_f3_f33( rgbPost, invert_f33(RRT_SAT_MAT));
  
  rgbPost = clamp_f3( rgbPost, 0., 65504.);

  // --- RGB rendering space to ACES --- //
  float3 aces = mult_f3_f33( rgbPost, AP1_2_AP0_MAT);
  
  aces = clamp_f3( aces, 0., 65504.);

  // --- Red modifier --- //
  float hue = rgb_2_hue( aces);
  float centeredHue = center_hue( hue, RRT_RED_HUE);
  float hueWeight = cubic_basis_shaper( centeredHue, RRT_RED_WIDTH);

  float minChan; // UwU
  if ( centeredHue < 0.) // min_f3( aces) = aces.g (i.e. magenta-red)
    minChan = aces.g;
  else // min_f3( aces) = aces.b (i.e. yellow-red)
    minChan = aces.b;
  
  float a = hueWeight * ( 1. - RRT_RED_SCALE) - 1.;
  float b = aces.r - hueWeight * ( RRT_RED_PIVOT + minChan) * ( 1. - RRT_RED_SCALE);
  float c = hueWeight * RRT_RED_PIVOT * minChan * (1. - RRT_RED_SCALE);

  aces.r = ( -b - sqrt( b * b - 4. * a * c)) / ( 2. * a);

  // --- Glow module --- //
  float saturation = rgb_2_saturation( aces);
  float ycOut = rgb_2_yc( aces);
  float s = sigmoid_shaper( ( saturation - 0.4) * 5.);
  float reducedGlow = 1. + glow_inv( ycOut, RRT_GLOW_GAIN *s, RRT_GLOW_MID);

  aces = mult_f_f3( reducedGlow, aces);
  return aces;
}

#endif // _ACES_LIB_RRT_COMMON