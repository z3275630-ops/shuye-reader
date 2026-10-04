#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uProgress;
uniform sampler2D uPage;
out vec4 fragColor;
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float fold = 1.0 - uProgress * 1.15;
  float diagonal = uv.x + (uv.y - 0.5) * 0.12 * sin(uProgress * 3.14159);
  float distance = diagonal - fold;
  float radius = 0.085;
  if (distance < -radius) { fragColor = texture(uPage, uv); }
  else if (distance < 0.0) {
    float angle = asin(clamp((distance + radius) / radius,0.0,1.0));
    vec2 sampleUv = vec2(fold-radius+angle*radius,uv.y);
    vec4 front = texture(uPage,clamp(sampleUv,vec2(0.0),vec2(1.0)));
    fragColor = vec4(front.rgb * (0.82+0.18*cos(angle)),front.a);
  } else if (distance < radius) {
    vec2 mirrorUv=vec2(fold-distance,uv.y);
    vec4 back=texture(uPage,clamp(mirrorUv,vec2(0.0),vec2(1.0)));
    float shade=0.88+0.12*sin(distance/radius*3.14159);
    fragColor=vec4(mix(vec3(0.95,0.93,0.87),back.rgb,0.15)*shade,1.0);
  } else { fragColor=vec4(0.0); }
}
