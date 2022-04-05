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
#define NUM_SAMPLES 60
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

// 返回一个 [0,1] 之间的随机值
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

// 泊松采样
// 在 randomSeed周围进行采样？
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


// 返回平均d_Blocker
// 注意zReceiver的作用，计算所有遮挡物的平均dBlocker，zReceiver用来判断是不是遮挡物
float findBlocker( sampler2D shadowMap,  vec2 uv, float zReceiver ) {
  poissonDiskSamples(uv);

  //首先，确定一个范围，取这个范围内得blocker的平均depth

  //@@
  float dBlockerRange = 1.0 / 400.0 * 40.0 ;

  float dBlocker = 0.0;
  int count = 0;
  for(int i=0;i<BLOCKER_SEARCH_NUM_SAMPLES;i++){

      vec4 map_value = texture2D(shadowMap, uv + poissonDisk[i] * dBlockerRange);
      float map_depth =unpack(map_value);

      if(map_depth + 0.001> zReceiver)continue;

      dBlocker+=map_depth;
      count+=1;
  }

  //@@
  // if(count == BLOCKER_SEARCH_NUM_SAMPLES)return 2.0;

	return dBlocker/float(count);
}

float PCF(sampler2D shadowMap, vec4 coords, float filterSize) {
  // 与 shadowMap 不同，PCF不再是简单的二元值（1，0），而是根据 filter size 取一个中间值
  // 怎么取，首先 coords的 x,y是属于[0,1]的
  // 答案，已经内置泊松采样，直接用就行了
  poissonDiskSamples(coords.xy);
  // 我不知道这个泊松采样是怎么运作的，当然也就不知道它有个采样范围
  // 不知道这个filterSize是怎么得出来?
  // 如果 filterSize过大，则会导致在很大的范围内进行平均，就会是阴影变得过于模糊
  int ret=0;
  float camera_depth = coords.z;
  for(int i=0;i<NUM_SAMPLES;i++){
    vec4 map_value = texture2D(shadowMap,coords.xy + poissonDisk[i] * filterSize);
    float map_depth = unpack(map_value);  
    // 1e-2是bias
    if(abs(map_depth-camera_depth)<EPS||map_depth>camera_depth)ret+=1;
    // 这个 0.01 是 bias
    // if(map_depth > camera_depth - 0.01) ret+=1;
  }
  // float()强制转换
  return float(ret) / float(NUM_SAMPLES);
}

float PCSS(sampler2D shadowMap, vec4 coords){

  // STEP 1: avgblocker depth
  
  float avgBlocker_depth = findBlocker(shadowMap,coords.xy,coords.z); 

  // STEP 2: penumbra size

  //@@ 这个 0.1 如果小了的话， 会多出很多黑点
   if(avgBlocker_depth<0.0001)return 1.0;
  // if(avgBlocker_depth>2.0)return 0.0;/

  //感觉就是调参了，为了让效果更好
  float w_light = 1.0/30.0;

  float w_penumbra = (coords.z - avgBlocker_depth) * w_light / avgBlocker_depth;


  return PCF(shadowMap,coords, w_penumbra);
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
  // visibility = useShadowMap(uShadowMap, vec4(shadowCoord, 1.0));
  // visibility = PCF(uShadowMap, vec4(shadowCoord, 1.0), 1.0/400.0);
  visibility = PCSS(uShadowMap, vec4(shadowCoord, 1.0));

  vec3 phongColor = blinnPhong();

  gl_FragColor = vec4(phongColor * visibility , 1.0);
  // gl_FragColor = vec4(phongColor, 1.0);
}