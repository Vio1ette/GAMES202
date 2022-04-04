#ifdef GL_ES
precision mediump float;
#endif

// Phong related variables
uniform sampler2D uSampler;
uniform vec3 uKd;
uniform vec3 uKs;
uniform vec3 uLightPos;
uniform vec3 uCameraPos;
uniform vec3 uLightIntensity;

varying highp vec2 vTextureCoord;
varying highp vec3 vFragPos;
varying highp vec3 vNormal;

// Shadow map related variables
#define NUM_SAMPLES 20
#define BLOCKER_SEARCH_NUM_SAMPLES NUM_SAMPLES
#define PCF_NUM_SAMPLES NUM_SAMPLES
#define NUM_RINGS 10

#define EPS 1e-3
#define PI 3.141592653589793
#define PI2 6.283185307179586


uniform sampler2D uShadowMap;


varying vec4 vPositionFromLight;

highp float rand_1to1(highp float x ) { 
  // -1 -1
  return fract(sin(x)*10000.0);
}

highp float rand_2to1(vec2 uv ) { 
  // 0 - 1
	const highp float a = 12.9898, b = 78.233, c = 43758.5453;
	highp float dt = dot( uv.xy, vec2( a,b ) ), sn = mod( dt, PI );
	return fract(sin(sn) * c);
}

// 【】unpack干嘛用的
// 因为 RGBA 都是小于等于255的，所以可以用一个32位的float存储RGBA
float unpack(vec4 rgbaDepth) {
    const vec4 bitShift = vec4(1.0, 1.0/256.0, 1.0/(256.0*256.0), 1.0/(256.0*256.0*256.0));
    return dot(rgbaDepth, bitShift);
}

vec2 poissonDisk[NUM_SAMPLES];

void poissonDiskSamples( const in vec2 randomSeed ) {

  float ANGLE_STEP = PI2 * float( NUM_RINGS ) / float( NUM_SAMPLES );
  float INV_NUM_SAMPLES = 1.0 / float( NUM_SAMPLES );

  float angle = rand_2to1( randomSeed ) * PI2;
  float radius = INV_NUM_SAMPLES;
  float radiusStep = radius;

  for( int i = 0; i < NUM_SAMPLES; i ++ ) {
    poissonDisk[i] = vec2( cos( angle ), sin( angle ) ) * pow( radius, 0.75 );
    radius += radiusStep;
    angle += ANGLE_STEP;
  }
}

void uniformDiskSamples( const in vec2 randomSeed ) {

  float randNum = rand_2to1(randomSeed);
  float sampleX = rand_1to1( randNum ) ;
  float sampleY = rand_1to1( sampleX ) ;

  float angle = sampleX * PI2;
  float radius = sqrt(sampleY);

  for( int i = 0; i < NUM_SAMPLES; i ++ ) {
    poissonDisk[i] = vec2( radius * cos(angle) , radius * sin(angle)  );

    sampleX = rand_1to1( sampleY ) ;
    sampleY = rand_1to1( sampleX ) ;

    angle = sampleX * PI2;
    radius = sqrt(sampleY);
  }
}

float findBlocker( sampler2D shadowMap,  vec2 uv, float zReceiver ) {
	return 1.0;
}

float PCF(sampler2D shadowMap, vec4 coords) {
  // 与 shadowMap 不同，PCF不再是简单的二元值（1，0），而是根据 filter size 取一个中间值
  // 怎么取



  return 1.0;
}

float PCSS(sampler2D shadowMap, vec4 coords){

  // STEP 1: avgblocker depth

  // STEP 2: penumbra size

  // STEP 3: filtering
  
  return 1.0;

}


float useShadowMap(sampler2D shadowMap, vec4 shadowCoord){
  // 【】我想用lightMVP，但是我在这个文件中怎么调用CalcLightMVP获得lightMVP呢？
  // lightMVP好像已经帮你做过了（在顶点着色器中）

  // shading point 经过MVP（正交投影），齐次除法之后得到4维坐标shadowCoord 
  // 想下Unity Shader入门精要里面的内容
  // 齐次除法之后，最后得到的4维坐标，x,y都是屏幕空间坐标，z是深度信息，w是1
  vec4 map_value = texture2D(shadowMap,shadowCoord.st);
  float map_depth = unpack(map_value);

  // 【】很奇怪，camera_depth算是第二道pass中要得到的值，但是第二道pass不应该是正常的在相机空间的渲染，为什么还要用 lightMVP 将点坐标变换到 light space
  // vPositionFromLight = uLightMVP * vec4(aVertexPosition, 1.0);
  // 一个解释：aVertexPosition是相机空间中的点坐标，其中存着相机空间中的深度，不能用来和light space中的深度做比较（不同参考系下的长度没法比较）
  // 所以要将 aVertexxPosition 转换到light space中，获取其在 light space 下的深度，再进行比较
  float camera_depth = shadowCoord.z;

  // 我不理解！【】 只有一种解释，map_depth和camera_depth都是大于0的，所以值大的要深
  // 这里的深度，想想你是怎么写 near 和 far 的，你写 0.1->400，就是说已经把 z 值取正了，所以这样写是合理的，map_depth < camera_depth时被遮挡！
  return map_depth >= camera_depth ? 1.0 : 0.0;


}

vec3 blinnPhong() {
  vec3 color = texture2D(uSampler, vTextureCoord).rgb;
  color = pow(color, vec3(2.2));

  vec3 ambient = 0.05 * color;

  vec3 lightDir = normalize(uLightPos);
  vec3 normal = normalize(vNormal);
  float diff = max(dot(lightDir, normal), 0.0);
  vec3 light_atten_coff =
      uLightIntensity / pow(length(uLightPos - vFragPos), 2.0);
  vec3 diffuse = diff * light_atten_coff * color;

  vec3 viewDir = normalize(uCameraPos - vFragPos);
  vec3 halfDir = normalize((lightDir + viewDir));
  float spec = pow(max(dot(halfDir, normal), 0.0), 32.0);
  vec3 specular = uKs * light_atten_coff * spec;

  vec3 radiance = (ambient + diffuse + specular);
  vec3 phongColor = pow(radiance, vec3(1.0 / 2.2));
  return phongColor;
}

void main(void) {

  // shadowCoord.x = vPositionFromLight.x*uShadowMap.x/2+uShadowMap.x/2;
  // shadowCoord.y = vPositionFromLight.y*uShadowMap.y/2+uShadowMap.y/2;
  // shadowCoord.z =vPositionFromLight.z;
  // shadowCoord.w=vPositionFromLight.w;

  // 由于是正交投影，我觉得这里用不用齐次除法都一样，反正w是1 【】
  vec3 shadowCoord = vPositionFromLight.xyz;
  // 归一化至[0,1]，屏幕宽高都是1？【】
  // 想一下，shadowMap本质上就是一张纹理，其宽高就是1啊...好像是的，是这么回事
    shadowCoord= shadowCoord*0.5+0.5;

  float visibility;
  visibility = useShadowMap(uShadowMap, vec4(shadowCoord, 1.0));
  //visibility = PCF(uShadowMap, vec4(shadowCoord, 1.0));
  //visibility = PCSS(uShadowMap, vec4(shadowCoord, 1.0));

  vec3 phongColor = blinnPhong();

  gl_FragColor = vec4(phongColor * visibility , 1.0);
  // gl_FragColor = vec4(phongColor, 1.0);
}