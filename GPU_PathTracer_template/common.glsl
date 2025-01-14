/**
 * common.glsl
 * Common types and functions used for ray tracing.
 */

const float pi = 3.14159265358979;
const float epsilon = 0.001;

struct Ray {
    vec3 o;     // origin
    vec3 d;     // direction - always set with normalized vector
    float t;    // time, for motion blur
};

Ray createRay(vec3 o, vec3 d, float t)
{
    Ray r;
    r.o = o;
    r.d = d;
    r.t = t;
    return r;
}

Ray createRay(vec3 o, vec3 d)
{
    return createRay(o, d, 0.0);
}

vec3 pointOnRay(Ray r, float t)
{
    return r.o + r.d * t;
}

float gSeed = 0.0;

uint baseHash(uvec2 p)
{
    p = 1103515245U * ((p >> 1U) ^ (p.yx));
    uint h32 = 1103515245U * ((p.x) ^ (p.y>>3U));
    return h32 ^ (h32 >> 16);
}

float hash1(inout float seed) {
    uint n = baseHash(floatBitsToUint(vec2(seed += 0.1,seed += 0.1)));
    return float(n) / float(0xffffffffU);
}

vec2 hash2(inout float seed) {
    uint n = baseHash(floatBitsToUint(vec2(seed += 0.1,seed += 0.1)));
    uvec2 rz = uvec2(n, n * 48271U);
    return vec2(rz.xy & uvec2(0x7fffffffU)) / float(0x7fffffff);
}

vec3 hash3(inout float seed)
{
    uint n = baseHash(floatBitsToUint(vec2(seed += 0.1, seed += 0.1)));
    uvec3 rz = uvec3(n, n * 16807U, n * 48271U);
    return vec3(rz & uvec3(0x7fffffffU)) / float(0x7fffffff);
}

float rand(vec2 v)
{
    return fract(sin(dot(v.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 toLinear(vec3 c)
{
    return pow(c, vec3(2.2));
}

vec3 toGamma(vec3 c)
{
    return pow(c, vec3(1.0 / 2.2));
}

vec2 randomInUnitDisk(inout float seed) {
    vec2 h = hash2(seed) * vec2(1.0, 6.28318530718);
    float phi = h.y;
    float r = sqrt(h.x);
	return r * vec2(sin(phi), cos(phi));
}

vec3 randomInUnitSphere(inout float seed)
{
    vec3 h = hash3(seed) * vec3(2.0, 6.28318530718, 1.0) - vec3(1.0, 0.0, 0.0);
    float phi = h.y;
    float r = pow(h.z, 1.0/3.0);
	return r * vec3(sqrt(1.0 - h.x * h.x) * vec2(sin(phi), cos(phi)), h.x);
}

vec3 randomUnitVector(inout float seed) //to be used in diffuse reflections with distribution cosine
{
    return(normalize(randomInUnitSphere(seed)));
}

struct Camera
{
    vec3 eye;
    vec3 u, v, n;
    float width, height;
    float lensRadius;
    float planeDist, focusDist;
    float time0, time1;
};

Camera createCamera(
    vec3 eye,
    vec3 at,
    vec3 worldUp,
    float fovy,
    float aspect,
    float aperture,  //diametro em multiplos do pixel size
    float focusDist,  //focal ratio
    float time0,
    float time1)
{
    Camera cam;
    if(aperture == 0.0) cam.focusDist = 1.0; //pinhole camera then focus in on vis plane
    else cam.focusDist = focusDist;
    vec3 w = eye - at;
    cam.planeDist = length(w);
    cam.height = 2.0 * cam.planeDist * tan(fovy * pi / 180.0 * 0.5);
    cam.width = aspect * cam.height;

    cam.lensRadius = aperture * 0.5 * cam.width / iResolution.x;  //aperture ratio * pixel size; (1 pixel=lente raio 0.5)
    cam.eye = eye;
    cam.n = normalize(w);
    cam.u = normalize(cross(worldUp, cam.n));
    cam.v = cross(cam.n, cam.u);
    cam.time0 = time0;
    cam.time1 = time1;
    return cam;
}

Ray getRay(Camera cam, vec2 pixel_sample)  //rnd pixel_sample viewport coordinates
{
    vec2 ls = cam.lensRadius * randomInUnitDisk(gSeed);  //ls - lens sample for DOF
    float time = cam.time0 + hash1(gSeed) * (cam.time1 - cam.time0);
    
    //Calculate eye_offset and ray direction

    vec3 ps = vec3(
        cam.width * (pixel_sample.x / iResolution.x - 0.5f), 
        cam.height * (pixel_sample.y / iResolution.y - 0.5f),
        -cam.planeDist);

    // vec3 d = ps;

    // vec3 eye = cam.eye;
    // vec3 ray_dir = normalize(cam.u * d.x + cam.v * d.y + cam.n * d.z);

    vec3 d, eye;
    vec3 l = vec3(ls.x * cam.lensRadius, ls.y * cam.lensRadius, 0.0);
    vec3 p = ps * (cam.focusDist / cam.lensRadius);

    eye = cam.eye + cam.u * l.x + cam.v * l.y;
    d = p - l;

    vec3 ray_dir = normalize(d.x * cam.u + cam.v * d.y + cam.n * d.z);

    return createRay(eye, ray_dir, time);
}

// MT_ material type
#define MT_DIFFUSE 0
#define MT_METAL 1
#define MT_DIALECTRIC 2

struct Material
{
    int type;
    vec3 albedo;  //diffuse color
    vec3 specColor;  //the color tint for specular reflections. for metals and opaque dieletrics like coloured glossy plastic
    vec3 emissive; //
    float roughness; // controls roughness for metals. It can be used for rough refractions
    float refIdx; // index of refraction for dialectric
    vec3 refractColor; // absorption for beer's law
};

Material createDiffuseMaterial(vec3 albedo)
{
    Material m;
    m.type = MT_DIFFUSE;
    m.albedo = albedo;
    m.specColor = vec3(0.0);
    m.roughness = 1.0;  //ser usado na iluminação direta
    m.refIdx = 1.0;
    m.refractColor = vec3(0.0);
    m.emissive = vec3(0.0);
    return m;
}

Material createMetalMaterial(vec3 specClr, float roughness)
{
    Material m;
    m.type = MT_METAL;
    m.albedo = vec3(0.0);
    m.specColor = specClr;
    m.roughness = roughness;
    m.emissive = vec3(0.0);
    return m;
}

Material createDialectricMaterial(vec3 refractClr, float refIdx, float roughness)
{
    Material m;
    m.type = MT_DIALECTRIC;
    m.albedo = vec3(0.0);
    m.specColor = vec3(0.04);
    m.refIdx = refIdx;
    m.refractColor = refractClr;  
    m.roughness = roughness;
    m.emissive = vec3(0.0);
    return m;
}

struct HitRecord
{
    vec3 pos;
    vec3 normal;
    float t;            // ray parameter
    Material material;
};

float schlick(float cosine, float refIdx)
{
    float r0 = (1.0 - refIdx) / (1.0 + refIdx);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow((1.0 - cosine), 5.0);
}

bool scatter(Ray rIn, HitRecord rec, out vec3 atten, out Ray rScattered)
{
    if(rec.material.type == MT_DIFFUSE)
    {
        //consider the diffuse reflection
        rScattered = createRay(rec.pos + epsilon * rec.normal, rec.normal + randomUnitVector(gSeed));
        atten = rec.material.albedo * max(dot(rScattered.d, rec.normal), 0.0) / pi;
        return true;
    }
    if(rec.material.type == MT_METAL)
    {
        vec3 reflected = reflect(normalize(rIn.d), rec.normal);
        rScattered = createRay(rec.pos + epsilon * rec.normal, reflected);
        atten = rec.material.specColor;
        return true;
    }
    if(rec.material.type == MT_DIALECTRIC)
    {
        atten = vec3(1.0);
        vec3 outwardNormal;
        float niOverNt;
        float cosine;
        bool tir = false;

        if(dot(rIn.d, rec.normal) > 0.0) //hit inside
        {
            outwardNormal = -rec.normal;
            niOverNt = rec.material.refIdx;
            cosine = -dot(rIn.d, rec.normal);

            if (niOverNt > 1.0) {
                float sinT2 = niOverNt * niOverNt * (1.0 - cosine * cosine);
                if (sinT2 > 1.0)
                    tir = true;
                cosine = sqrt(1.0 - sinT2);
            }

            atten = exp(-rec.material.refractColor * rec.t);
        }
        else  //hit from outside
        {
            outwardNormal = rec.normal;
            niOverNt = 1.0 / rec.material.refIdx;
            cosine = -dot(rIn.d, rec.normal); 
        }

        float reflectProb;

        if (tir)
            reflectProb = 1.0;  
        else reflectProb = schlick(cosine, rec.material.refIdx);

        if( hash1(gSeed) < reflectProb)  //Reflection
        {
            vec3 reflected = reflect(normalize(rIn.d), outwardNormal);
            rScattered = createRay(rec.pos + epsilon * outwardNormal, reflected);
        }
        
        else  //Refraction
        {
            vec3 refracted = refract(normalize(rIn.d), outwardNormal, niOverNt);
            rScattered = createRay(rec.pos - epsilon * outwardNormal, refracted);
        }

        return true;
    }
    return false;
}

struct Triangle {vec3 a; vec3 b; vec3 c; };

Triangle createTriangle(vec3 v0, vec3 v1, vec3 v2)
{
    Triangle t;
    t.a = v0; t.b = v1; t.c = v2;
    return t;
}

bool hit_triangle(Triangle tr, Ray r, float tmin, float tmax, out HitRecord rec)
{
    //calculate a valid t and normal
    vec3 a1 = tr.b - tr.a;
    vec3 a2 = tr.c - tr.a;
    vec3 normal = normalize(cross(a1, a2));
    vec3 h = cross(r.d, a2);

    float a = dot(a1, h);
    float f = 1.0 / a;
    vec3 s = r.o - tr.a;
    float u = f * dot(s, h);

    if(u < 0.0 || u > 1.0) return false;

    vec3 q = cross(s, a1);
    float v = f * dot(r.d, q);

    if(v < 0.0 || u + v > 1.0) return false;

    float t = f * dot(a2, q);

    if(t < tmax && t > tmin)
    {
        rec.t = t;
        rec.normal = normal;
        rec.pos = pointOnRay(r, rec.t);
        return true;
    }
    return false;
}

struct Sphere
{
    vec3 center;
    float radius;
};

Sphere createSphere(vec3 center, float radius)
{
    Sphere s;
    s.center = center;
    s.radius = radius;
    return s;
}


struct MovingSphere
{
    vec3 center0, center1;
    float radius;
    float time0, time1;
};

MovingSphere createMovingSphere(vec3 center0, vec3 center1, float radius, float time0, float time1)
{
    MovingSphere s;
    s.center0 = center0;
    s.center1 = center1;
    s.radius = radius;
    s.time0 = time0;
    s.time1 = time1;
    return s;
}

vec3 center(MovingSphere mvsphere, float time)
{
    return mvsphere.center0 + (mvsphere.center1 - mvsphere.center0) * (time - mvsphere.time0) / (mvsphere.time1 - mvsphere.time0);
}


/*
 * The function naming convention changes with these functions to show that they implement a sort of interface for
 * the book's notion of "hittable". E.g. hit_<type>.
 */

bool hit_sphere(Sphere s, Ray r, float tmin, float tmax, out HitRecord rec)
{
    //calculate a valid t and normal
    vec3 co = r.o - s.center;
    vec3 u = normalize(r.d);
    
    float b = 2.0 * dot(u, co);
    float c = dot(co, co) - s.radius * s.radius;
    if(c > 0.0 && b > 0.0) return false;

    float a = dot(u, u);
    float delta = b*b - 4.0*a*c;
    if(delta < 0.0) return false;

    float t1 = (-b - sqrt(delta)) / (2.0*a);
    float t2 = (-b + sqrt(delta)) / (2.0*a);

    float t = min(t1, t2);

    vec3 pos = pointOnRay(r, t);
    vec3 normal = normalize(pos - s.center);
    if(s.radius < 0.0) normal *= -1.0;

    if(t < tmax && t > tmin) {
        rec.t = t;
        rec.pos = pos;
        rec.normal = normal;
        return true;
    }
    else return false;
}

bool hit_movingSphere(MovingSphere s, Ray r, float tmin, float tmax, out HitRecord rec)
{
    float B, C, delta;
    bool outside;
    float t;

    vec3 center = center(s, r.t);

    vec3 co = r.o - center;
    vec3 u = normalize(r.d);

    B = 2.0 * dot(u, co);
    C = dot(co, co) - s.radius * s.radius;
    if(C > 0.0 && B > 0.0) return false;

    float a = dot(u, u);
    delta = B*B - 4.0*a*C;
    if(delta < 0.0) return false;

    float t1 = (-B - sqrt(delta)) / (2.0*a);
    float t2 = (-B + sqrt(delta)) / (2.0*a);

    t = min(t1, t2);

    vec3 normal = normalize(pointOnRay(r, t) - center);
    if(s.radius < 0.0) rec.normal *= -1.0;
    
    if(t < tmax && t > tmin) {
        rec.t = t;
        rec.pos = pointOnRay(r, rec.t);
        rec.normal = normal;
        return true;
    }
    else return false;
}

struct pointLight {
    vec3 pos;
    vec3 color;
};

pointLight createPointLight(vec3 pos, vec3 color) 
{
    pointLight l;
    l.pos = pos;
    l.color = color;
    return l;
}