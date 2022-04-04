class DirectionalLight {

    constructor(lightIntensity, lightColor, lightPos, focalPoint, lightUp, hasShadowMap, gl) {
        this.mesh = Mesh.cube(setTransform(0, 0, 0, 0.2, 0.2, 0.2, 0));
        this.mat = new EmissiveMaterial(lightIntensity, lightColor);

        // how to use these three attributes to create the look-at matrix for light?
        // why is focalPoint {0,0,0}? does that mean focalPoint is  
        this.lightPos = lightPos;
        this.focalPoint = focalPoint;
        this.lightUp = lightUp;

        this.hasShadowMap = hasShadowMap;
        this.fbo = new FBO(gl);
        if (!this.fbo) {
            console.log("无法设置帧缓冲区对象");
            return;
        }
    }
    //【】I'm confused about that there's just one CalcLightMVP function.
    //it means that only one MVP matrix will be created.
    // But doesn't there need two MVP? I mean, one for light and one for real camera.
    CalcLightMVP(translate, scale) { // where are the translate and scale from? 这是针对模型的平移缩放，不是针对视锥体的
        let lightMVP = mat4.create();
        let modelMatrix = mat4.create();
        let viewMatrix = mat4.create();
        let projectionMatrix = mat4.create();

        // @@Model transform ************************************
        // 为什么模型变换需要 平移缩放旋转矩阵？ 
        // 想象移动模型，你鼠标的旋转操作会给出theta角度，键盘WASD会给出一个平移操作，这些都是模型变换需要的参数，在游戏中实时传入来控制角色自身
        // 模型变换矩阵就是模型根节点的Transform（缩放、旋转、平移），位于模型空间中的点通过模型变换矩阵就可以变换到世界空间
        // 【】为什么这里是先平移再缩放？反过来行不行？
        mat4.translate(modelMatrix,modelMatrix,translate);
        mat4.scale(modelMatrix,modelMatrix,scale);

        // @@View transform **********************************************

        // regard the light as the camera
        // lightPos -> lightDir, like vec{g}
        // focalpoint -> origin, like e
        // lightUp, like vec{t}
        // let T_view = mat4.create();

        // let _g = vec3.create();
        // vec3.set(_g, -this.lightPos[0], -this.lightPos[1], -this.lightPos[2]);

        // let g_cross_t = vec3.create();
        // vec3.cross(g_cross_t, this.lightPos, this.lightUp);

        // let R_view = mat4.create();
        // mat4.set(R_view, g_cross_t[0], this.lightUp[0], _g[0], 0, g_cross_t[1], this.lightUp[1], _g[1], 0, g_cross_t[2], this.lightUp[2], _g[2], 0, 0, 0, 0, 1);

        // mat4.multiply(viewMatrix, R_view, T_view);
        // 【】有时间把这个lookAt源码看一下，和之前的view矩阵好好对比一下
        mat4.lookAt(viewMatrix,this.lightPos,this.focalPoint,this.lightUp);
        
        // //打印view matrix
        // var matrixStr = "";
        // var counter = 0;
        // for (let idx in viewMatrix) {
        //     matrixStr += viewMatrix[idx] + ", "
        //     counter++;
        //     if (counter >= 4) {
        //         counter = 0;
        //         matrixStr += '\n';
        //     }
        // }
        // console.log(matrixStr);

        // @@Projection transform ***************************************** 
        //投影矩阵要自己设定上下左右远近，自己设定视锥体的参数
        
        //参数来源？我也不知道这些参数都是怎么来的，是参考这个博客：https://blog.csdn.net/qq_36242312/article/details/117562881
        //视锥体上下左右参数
        let right=100;
        let left=-right;
        let top =100;
        let bottom = -top;
        //视锥体 前后参数
        let near = 0.01;
        let far= 400;
        // orthographic projection，【】看ortho源码发现，其正交投影矩阵计算方式和课上讲的稍有区别
        mat4.ortho(projectionMatrix,left,right,bottom,top,near,far);


        // @@finally
        mat4.multiply(lightMVP, projectionMatrix, viewMatrix);
        mat4.multiply(lightMVP, lightMVP, modelMatrix);

        return lightMVP;
    }
}
