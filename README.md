## Installation

To start using FoliageFlow copy the plugin to the folder `res://addons/FoliageFlow/`.
 Then go to **Project > Project Settings > Plugins** and turn on **FoliageFlow**.

## Usage

Here is how to use FoliageFlow:

1. First add a **FoliageFlow** node.

2. Next add a **MultiMeshInstance3D**. Set it as the **Target** for **FoliageFlow**.

3. Assign a **MultiMesh** to the **MultiMeshInstance3D**. This is where you choose your foliage mesh.

4. Select **FoliageFlow**. Use the **Paint** or **Erase** tools, in the 3D editor toolbar.

5. Save the scene. **FoliageFlow** saves the painted transforms in
 the target **MultiMesh** so they come back automatically when you open the scene again.

6. After you are done painting you can remove the **FoliageFlow** node. Even delete the plugin.
 The painted foliage is saved in the **MultiMeshInstance3D** so your foliage stays the same.
