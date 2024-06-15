////////////////////////////////////////////////////////////////////////////////////////////////
//
// DH_UBER_MASK_DEPTH_ONLY 0.3.1
//
// This shader is free, if you paid for it, you have been ripped and should ask for a refund.
//
// This shader is developed by AlucardDH (Damien Hembert)
//
// Get more here : https://github.com/AlucardDH/dh-reshade-shaders
//
////////////////////////////////////////////////////////////////////////////////////////////////
#include "Reshade.fxh"


namespace DH_DEPTH_UBER_MASK_DEPTH_ONLY {

// Textures
    texture beforeTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
    sampler depthMaskbeforeSampler  { Texture = beforeTex; };


// Parameters    
    /*
    uniform float fTest <
        ui_type = "slider";
        ui_min = 0.0; ui_max = 10.0;
        ui_step = 0.001;
    > = 0.001;
    uniform bool bTest = true;
    uniform bool bTest2 = true;
    uniform bool bTest3 = true;
    */
    
    uniform int iDebug <
        ui_category = "Debug";
        ui_type = "combo";
        ui_label = "Display";
        ui_items = "Output\0Full Mask\0Mask overlay\0";
        ui_tooltip = "Debug the intermediate steps of the shader";
    > = 0;

// Depth mask

    uniform float3 fDepthMaskNear <
        ui_text = "Center/Range/Strength:";
        ui_type = "slider";
        ui_category = "Depth mask";
        ui_label = "Near";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Leave these values at 0 for Menu Fix";
    > = float3(0.0,0.0,0.0);
    
    uniform float3 fDepthMaskMid <
        ui_type = "slider";
        ui_category = "Depth mask";
        ui_label = "Mid";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Leave these values at 0 for Menu Fix";
    > = float3(0.0,0.0,0.0);

    uniform float3 fDepthMaskFar <
        ui_type = "slider";
        ui_category = "Depth mask";
        ui_label = "Far";
        ui_min = 0.0; ui_max = 1.0;
        ui_step = 0.001;
        ui_tooltip = "Leave these at 1.0, 0.001, 1.0 for Menu Fix";
    > = float3(1.0,0.001,1.000);

// PS

    void PS_Save(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        outColor = getColor(coords);
    }
    
    float computeMask(float value, float3 params) {
    	if(value<=params[0]) {
    		return smoothstep(params[0]-params[1],params[0],value)*params[2];
    	} else {
    		return (1.0-smoothstep(params[0],params[0]+params[1],value))*params[2];
    	}
    }
    
    
    void PS_Apply(float4 vpos : SV_Position, float2 coords : TexCoord, out float4 outColor : SV_Target0) {
        float4 afterColor = getColor(coords);
        float4 beforeColor = getColorSampler(beforeSampler ,coords);

        float mask = 0.0;
        
        float depth = ReShade::GetLinearizedDepth(coords);
        mask += computeMask(depth,fDepthMaskNear);
        mask += computeMask(depth,fDepthMaskMid);
        mask += computeMask(depth,fDepthMaskFar);

		mask = saturate(mask);
		outColor = lerp(beforeColor,afterColor,1.0-mask);
  	if(iDebug==1) {
        	outColor = float4(mask,mask,mask,1.0);
		} else if(iDebug==2) {
        	outColor = lerp(afterColor,float4(0,1,0,1),mask);
		}
    }


// TEHCNIQUES 
    
    technique DH_DEPTH_UBER_MASK_DEPTH_ONLY_BEFORE<
        ui_label = "Depth_Mask_DEPTH_ONLY_BEFORE";
        c
    > {
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_Save;
            RenderTarget = beforeTex;
        }
    }

    technique DH_DEPTH_UBER_MASK_DEPTH_ONLY_AFTER<
        ui_label = "Depth_Mask_DEPTH_ONLY_AFTER";
        ui_tooltip = "Place this at the very bottom of your shader list for menu fix"
    > {
        pass {
            VertexShader = PostProcessVS;
            PixelShader = PS_Apply;
        }
    }

}