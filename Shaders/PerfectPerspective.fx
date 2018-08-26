/*
Copyright (c) 2018 Jacob Maximilian Fober

This work is licensed under the Creative Commons 
Attribution-ShareAlike 4.0 International License. 
To view a copy of this license, visit 
http://creativecommons.org/licenses/by-sa/4.0/.
*/

// Perfect Perspective PS ver. 2.3.0

  ////////////////////
 /////// MENU ///////
////////////////////

#ifndef ShaderAnalyzer
uniform int FOV <
	ui_label = "Field of View";
	ui_tooltip = "Match in-game Field of View";
	ui_type = "drag";
	ui_min = 45; ui_max = 120;
	ui_category = "Distortion";
> = 90;

uniform float Vertical <
	ui_label = "Vertical Amount";
	ui_tooltip = "0.0 - cylindrical projection \n"
		"1.0 - spherical projection";
	ui_type = "drag";
	ui_min = 0.0; ui_max = 1.0;
	ui_category = "Distortion";
> = 0.618;

uniform int Type <
	ui_label = "Type of FOV";
	ui_tooltip = "If the image bulges in movement (too high FOV), change it to 'Diagonal' \n"
		"When proportions are distorted at the periphery (too low FOV), choose 'Vertical'";
	ui_type = "combo";
	ui_items = "Horizontal FOV\0Diagonal FOV\0Vertical FOV\0";
	ui_category = "Distortion";
> = 0;

uniform float4 Color <
	ui_label = "Color";
	ui_tooltip = "Use Alpha to adjust opacity";
	ui_type = "Color";
	ui_category = "Borders";
> = float4(0.027, 0.027, 0.027, 0.902);

uniform bool Borders <
	ui_label = "Mirrored Borders";
	ui_category = "Borders";
> = true;

uniform float Zooming <
	ui_label = "Border Scale";
	ui_type = "drag";
	ui_min = 0.0; ui_max = 3.0; ui_step = 0.001;
	ui_category = "Borders";
> = 1.0;

uniform bool Debug <
	ui_label = "Display Resolution Map";
	ui_tooltip = "Color map of the Resolution Scale \n"
		" (Green) - Supersampling \n"
		" ( Red ) - Undersampling";
	ui_category = "Debug Tools";
> = false;

uniform float ResScale <
	ui_label = "DSR scale factor";
	ui_tooltip = "(DSR) Dynamic Super Resolution... \n"
		"Simulate application running beyond-native screen resolution";
	ui_type = "drag";
	ui_min = 1.0; ui_max = 8.0; ui_step = 0.02;
	ui_category = "Debug Tools";
> = 1.0;
#endif

  //////////////////////
 /////// SHADER ///////
//////////////////////

#include "ReShade.fxh"

// Define screen texture with mirror tiles
sampler SamplerColor
{
	Texture = ReShade::BackBufferTex;
	AddressU = MIRROR;
	AddressV = MIRROR;
};

// Stereographic-Gnomonic lookup function by Jacob Max Fober
// Input data:
	// FOV >> Camera Field of View in degrees
	// Coordinates >> UV coordinates (from -1, to 1), where (0,0) is at the center of the screen
float Formula(float2 Coordinates)
{
	// Convert 1/4 FOV to radians and calc tangent squared
	float SqrTanFOVq = tan(radians(float(FOV) * 0.25));
	SqrTanFOVq *= SqrTanFOVq;
	return (1.0 - SqrTanFOVq) / (1.0 - SqrTanFOVq * dot(Coordinates, Coordinates));
}

// Shader pass
float3 PerfectPerspectivePS(float4 vois : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	// Get Aspect Ratio
	float AspectR = 1.0 / ReShade::AspectRatio;
	// Get Screen Pixel Size
	float2 ScrPixelSize = ReShade::PixelSize;

	// Convert FOV type..
	float FovType = (Type == 1) ? sqrt(AspectR * AspectR + 1.0) : Type == 2 ? AspectR : 1.0;

	// Convert UV to Radial Coordinates
	float2 SphCoord = texcoord * 2.0 - 1.0;
	// Aspect Ratio correction
	SphCoord.y *= AspectR;
	// Zoom in image and adjust FOV type (pass 1 of 2)
	SphCoord *= Zooming / FovType;

	// Stereographic-Gnomonic lookup, vertical distortion amount and FOV type (pass 2 of 2)
	SphCoord *= Formula(float2(SphCoord.x, sqrt(Vertical) * SphCoord.y)) * FovType;

	// Aspect Ratio back to square
	SphCoord.y /= AspectR;

	// Get Pixel Size in stereographic coordinates
	float2 PixelSize = fwidth(SphCoord);

	// Outside borders check with Anti-Aliasing
	float2 AtBorders = smoothstep( 1 - PixelSize, PixelSize + 1, abs(SphCoord) );

	// Back to UV Coordinates
	SphCoord = SphCoord * 0.5 + 0.5;

	// Sample display image
	float3 Display = tex2D(SamplerColor, SphCoord).rgb;

	// Mask outside-border pixels or mirror
	Display = lerp(
		Display, 
		lerp(
			Borders ? Display : tex2D(SamplerColor, texcoord).rgb, 
			Color.rgb, 
			Color.a
		), 
		max(AtBorders.x, AtBorders.y)
	);

	// Output type choice
	if (Debug)
	{
		// Calculate Pixel Size difference
		PixelSize = ScrPixelSize / PixelSize;
		PixelSize /= ResScale; // simulate Dynamic Super Resolution (DSR)
		float PixelScale = min(PixelSize.x, PixelSize.y);
		// Separate supersampling and undersampling scalars
		PixelSize.x = min(PixelScale, 0.5) * 2;
		PixelSize.y = max(PixelScale, 0.5) * 2 - 1;

		// Define Mapping colors
		float3 SuperSampl = float3(0, 1, 0.2); // Green
		float3 UnderSampl = float3(1, 0, 0.2); // Red
		float Neutral = 0.0625; // Black

		// Map scale-to-colors
		SuperSampl = lerp(SuperSampl, Neutral, PixelSize.x);
		UnderSampl = lerp(Neutral, UnderSampl, PixelSize.y);
		// Super-Under sampling mask
		float SuperUnderMask = min(floor(PixelScale * 2), 1);
		// Return 3-color scale map
		float3 ResMap = lerp(SuperSampl, UnderSampl, SuperUnderMask);
		ResMap = saturate(ResMap);
		// Blend scale map with background
		return normalize(ResMap) * (length(Display) * 0.8 + 0.2);
	}
	else
	{
		return Display;
	}
}

technique PerfectPerspective
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PerfectPerspectivePS;
	}
}
