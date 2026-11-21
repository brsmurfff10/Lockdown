import bpy
print("FLOW", [p.identifier for p in bpy.types.FluidFlowSettings.bl_rna.properties])
print("DOM", [p.identifier for p in bpy.types.FluidDomainSettings.bl_rna.properties])
