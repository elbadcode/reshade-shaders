/*
    Description : LAB Color Mask for Reshade https://reshade.me/
    Author      : elbadcode
    License     : MIT, Copyright (c) 2024 elbadcode

    MIT License
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    
*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

namespace badlabmask
{
    //// PREPROCESSOR DEFINITIONS ///////////////////////////////////////////////////

    //// UI ELEMENTS ////////////////////////////////////////////////////////////////
      uniform bool maskLab <
        ui_label = "LAB Mask";
        ui_tooltip ="enable the LAB space chroma mask";
    > = true;
    
        uniform bool desaturate<
        ui_label = "Desaturate";
        ui_tooltip ="apply the mask to color intensity not just to alpha, useful for previewing the output ";
    > = true;
    
    uniform float3 keyColor <
    __UNIFORM_COLOR_FLOAT3
        ui_label = "Key color";
        ui_tooltip = "Key color";
        ui_category = "Key color";
        >  = float3(0.2f, 0.65f, 0.6f);

    uniform float closeMatch <
        ui_label = "Close";
        ui_tooltip = "High confidence match threshold in LAB delta E where we consider colors identical. Scaled such that 0 is identical, under 10 is very close, and 100 is about as far as you can get. Taking the delta E compared to black is equivalent to L or luminance alone and would give you a dE of 100 with a pure white key";
        ui_category = "Key color";
        ui_type = "slider";
        ui_min = 0.0;
        ui_max = 50.0;
        > = 5.0;

   uniform float farMatch <
        ui_label = "Far";
        ui_tooltip = "Low confidence match threshold in LAB delta E. Colors between the two thresholds will be faded by smoothing factor. This can serve to reduce outlines without making targets translucent";
        ui_category = "Key color";
        ui_type = "slider";
        ui_min = 0.0;
        ui_max = 100.0;
        > = 12.0;

    uniform float smoothing <
        ui_label = "Smoothing";
        ui_tooltip = "";
        ui_category = "Smoothing factor. Multiplied by 100 for ease of selection";
        ui_type = "slider";
        ui_min = 0.0;
        ui_max = 1.0;
        > = 0.7;

    //// DEFINES ////////////////////////////////////////////////////////////////////
    #define mod(x, y) (x - y * floor(x / y))
    //D65
    static const float3x3 sRGB_To_XYZ_M = float3x3(
    0.4124564,  0.3575761,  0.1804375,
    0.2126729,  0.7151522,  0.0721750,
    0.0193339,  0.1191920,  0.9503041);

    //D65 (0)
    static const float3x3 XYZ_To_sRGB = float3x3(
    3.2404542, -1.5371385, -0.4985314,
   -0.9692660,  1.8760108,  0.0415560,
    0.0556434, -0.2040259,  1.0572252);


static const float TWO_PI = 6.28318530718;
static const float  PI = 3.14159265359;


    //will add other color spaces as inputs if I ever update this. YUV sampling would also be ideal

	static const float3 D65_WHITE = float3(0.95045592705, 1.0, 1.08905775076);
    //// FUNCTIONS //////////////////////////////////////////////////////////////////
    float3 LinearTosRGB( float3 color )
    {
        float3 x = color * 12.92f;
        float3 y = 1.055f * pow(saturate(color), 1.0f / 2.4f) - 0.055f;

        float3 clr = color;
        clr.r = color.r < 0.0031308f ? x.r : y.r;
        clr.g = color.g < 0.0031308f ? x.g : y.g;
        clr.b = color.b < 0.0031308f ? x.b : y.b;

        return clr;
    }

    float3 SRGBToLinear( float3 color )
    {
        float3 x = color / 12.92f;
        float3 y = pow(max((color + 0.055f) / 1.055f, 0.0f), 2.4f);

        float3 clr = color;
        clr.r = color.r <= 0.04045f ? x.r : y.r;
        clr.g = color.g <= 0.04045f ? x.g : y.g;
        clr.b = color.b <= 0.04045f ? x.b : y.b;

        return clr;
    }
    
    float XYZ_TO_LAB_F(float x)
	 {
    return x > 0.00885645167 ?( pow(x, 0.333333333)) :( 7.78703703704 * x + 0.13793103448);
	}
	
	
	
	
	float3 XYZ_TO_LAB(float3 xyz) {
    float3 xyz_scaled = xyz /D65_WHITE;
    xyz_scaled = float3(XYZ_TO_LAB_F(xyz_scaled.x), XYZ_TO_LAB_F(xyz_scaled.y), XYZ_TO_LAB_F(xyz_scaled.z));
    return float3(
        (116.0 * xyz_scaled.y) - 16.0,
        500.0 * (xyz_scaled.x - xyz_scaled.y),
        200.0 * (xyz_scaled.y - xyz_scaled.z)
    );
}
float LAB_TO_XYZ_F(float x) {
    //                                     3*(6/29)^2         4/29
    return (x > 0.206897) ? x * x * x : (0.12841854934 * (x - 0.137931034));
}
float3 LAB_TO_XYZ(float3 Lab) {
    float w = (Lab.x + 16.0) / 116.0;
    return D65_WHITE * float3(
        LAB_TO_XYZ_F(w + Lab.y / 500.0),
        LAB_TO_XYZ_F(w),
        LAB_TO_XYZ_F(w - Lab.z / 200.0)
    );
}

float3 sRGB_TO_XYZ( float3 c )
{
    return mul(  sRGB_To_XYZ_M , c );
}


float3 SRGB_TO_LAB(float3 srgb){
return XYZ_TO_LAB(sRGB_TO_XYZ(srgb));
}


//courtesy of https://github.com/Rachmanin0xFF/GLSL-Color-Functions
float LAB_DELTA_E_CIE2000(float3 lab1, float3 lab2) {
    // b = bar
    // p = prime
    float Cb7 = pow((sqrt(lab1.y*lab1.y + lab1.z*lab1.z) + sqrt(lab1.y*lab1.y + lab1.z*lab1.z))*0.5, 7.0);
    //                                 25^7
    float G = 0.5*(1.0-sqrt(Cb7/(Cb7 + 6103515625.0)));

    float ap1 = lab1.y*(1.0 + G);
    float ap2 = lab2.y*(1.0 + G);

    float Cp1 = sqrt(ap1*ap1 + lab1.z*lab1.z);
    float Cp2 = sqrt(ap2*ap2 + lab2.z*lab2.z);
    
    float hp1 = atan2(lab1.z, ap1);
    float hp2 = atan2(lab2.z, ap2);
    if(hp1 < 0.0) hp1 = TWO_PI + hp1;
    if(hp2 < 0.0) hp2 = TWO_PI + hp2;
    
    float dLp = lab2.x - lab1.x;
    float dCp = Cp2 - Cp1;
    float dhp = hp2 - hp1;
    dhp += (dhp>PI) ? -TWO_PI: (dhp<-PI) ? TWO_PI : 0.0;
    // don't need to handle Cp1*Cp2==0 case because it's implicitly handled by the next line
    float dHp = 2.0*sqrt(Cp1*Cp2)*sin(dhp/2.0);
    
    float Lbp = (lab1.x + lab2.x)*0.5;
    float Cbp = sqrt(Cp1 + Cp2)/2.0;
    float Cbp7 = pow(Cbp, 7.0);
    
    // CIEDE 2000 Color-Difference \Delta E_{00}
    // This where everyone messes up (because it's a pain)
    // it's also the source of the discontinuity...
    
    // We need to average the angles h'_1 and h'_2 (hp1 and hp2) here.
    // This is a surprisingly nontrivial task.
    // Credit to https://stackoverflow.com/a/1159336 for the succinct formula.
    float hbp = mod( ( hp1 - hp2 + PI), TWO_PI ) - PI;
    hbp = mod((hp2 + ( hbp / 2.0 ) ), TWO_PI);
    if(Cp1*Cp2 == 0.0) hbp = hp1 + hp2;
    
    //                             30 deg                                                  6 deg                            63 deg
    float T = 1.0 - 0.17*cos(hbp - 0.52359877559) + 0.24*cos(2.0*hbp) + 0.32*cos(3.0*hbp + 0.10471975512) - 0.2*cos(4.0*hbp - 1.09955742876);
    
    float dtheta = 30.0*exp(-(hbp - 4.79965544298)*(hbp - 4.79965544298)/25.0);
    float RC = 2.0*sqrt(Cbp7/(Cbp7 + 6103515625.0));
    
    float Lbp2 = (Lbp-50.0)*(Lbp-50.0);
    float SL = 1.0 + 0.015*Lbp2/sqrt(20.0 + Lbp2);
    float SC = 1.0 + 0.045*Cbp;
    float SH = 1.0 + 0.015*Cbp*T;
    
    float RT = -RC*sin(2.0*dtheta)/TWO_PI;
    
    return sqrt(dLp*dLp/(SL*SL) + dCp*dCp/(SC*SC) + dHp*dHp/(SH*SH) + RT*dCp*dHp/(SC*SH));
}


//branching is for noobs. no need for and if or ternary argument when we can resolve to a simple 1 or 0 
float when_gt(float x, float y) {
    return max(sign(x - y), 0.0f);
}

float when_le(float x, float y) {
    return 1.0f - when_gt(x, y);
}

float when_lt(float x, float y) {
    return max(sign(y - x), 0.0f);
}
    //// PIXEL SHADERS //////////////////////////////////////////////////////////////
    
    float4 PS_LabMask(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
    //this only affects alpha in screenshots. If possible I'd like to apply it in realtime to the whole game window but I'm unsure if that can be done
    float4 color= tex2D( ReShade::BackBuffer, texcoord );

    float3 key_color = SRGB_TO_LAB(keyColor);


   	float3 labcolor = SRGB_TO_LAB(color.rgb);
    float deltaE = LAB_DELTA_E_CIE2000(labcolor, key_color);
    //if low confidence match reduce alpha by smoothing factor
   float alpha = 1.0f;
    alpha -= when_le(deltaE,farMatch) * (1.0f - (deltaE * smoothing * 0.01f)); 
    //multiply by 0 if high confidence. Two step method works better than any single formula
     alpha *= when_gt(deltaE, closeMatch);
     float3 finalcolor = desaturate ? color.xyz * alpha : color.xyz;
  	return float4(finalcolor,  alpha);
	}
    
  

    

    //// TECHNIQUES /////////////////////////////////////////////////////////////////
    technique labMasking
    {
        pass lab_pass0
        {
            VertexShader   = PostProcessVS;
            PixelShader    = PS_LabMask;
        }
    }
    
}


