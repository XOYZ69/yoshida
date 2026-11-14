#ifndef YSTB_MATH_H
#define YSTB_MATH_H
double ystb_pow(double x, double y);
double ystb_fmod(double x, double y);
double ystb_cos(double x);
double ystb_acos(double x);
double ystb_ldexp(double x, int e);
#define floor(x) __builtin_floor(x)
#define ceil(x) __builtin_ceil(x)
#define sqrt(x) __builtin_sqrt(x)
#define fabs(x) __builtin_fabs(x)
#define pow(x, y) ystb_pow(x, y)
#define fmod(x, y) ystb_fmod(x, y)
#define cos(x) ystb_cos(x)
#define acos(x) ystb_acos(x)
#define ldexp(x, e) ystb_ldexp(x, e)
double ystb_sin(double x);
double ystb_tan(double x);
double ystb_atan2(double y, double x);
double ystb_round(double x);
#define sqrtf(x) __builtin_sqrtf(x)
#define fabsf(x) __builtin_fabsf(x)
#define floorf(x) __builtin_floorf(x)
#define ceilf(x) __builtin_ceilf(x)
#define isnan(x) __builtin_isnan(x)
#define sinf(x) ((float)ystb_sin(x))
#define cosf(x) ((float)ystb_cos(x))
#define tanf(x) ((float)ystb_tan(x))
#define acosf(x) ((float)ystb_acos(x))
#define atan2f(y, x) ((float)ystb_atan2(y, x))
#define fmodf(x, y) ((float)ystb_fmod(x, y))
#define roundf(x) ((float)ystb_round(x))
#endif
