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
#endif
