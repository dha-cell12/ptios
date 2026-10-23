#ifndef TLINK_NATIVE_TOUCH_REQUEST_H
#define TLINK_NATIVE_TOUCH_REQUEST_H
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <locale.h>
#ifdef __APPLE__
#include <xlocale.h>
#endif
// Numeric task boundary; the shared executor performs argument validation.
enum class TLinkNativeTouchKind { Tap, Swipe };
struct TLinkNativeTouchRequest {
    TLinkNativeTouchKind kind=TLinkNativeTouchKind::Tap;
    double x1=0,y1=0,x2=0,y2=0;
    int durationMs=50,finger=0,steps=0;
};
inline int TLinkNativeTouchTask(TLinkNativeTouchKind kind) {
    switch(kind){case TLinkNativeTouchKind::Tap:return 62;case TLinkNativeTouchKind::Swipe:return 63;}return 0;
}
// Preserve NSString %.2f -> floatValue and %.0f -> intValue compatibility
// without allocating a request string or mutating the process/thread locale.
// One immutable C numeric locale per process; no per-call locale creation.
#ifdef _WIN32
inline _locale_t TLinkNativeTouchLocale(){static _locale_t value=_create_locale(LC_NUMERIC,"C");return value;}
#elif defined(__APPLE__)
inline locale_t TLinkNativeTouchLocale(){static locale_t value=newlocale(LC_NUMERIC_MASK,"C",nullptr);return value;}
#endif
inline bool TLinkNativeTouchDecimal(char *out,size_t size,int precision,double value) {
#ifdef _WIN32
    const auto locale=TLinkNativeTouchLocale();
    if(!locale)return false;
    const int count=_snprintf_s_l(out,size,_TRUNCATE,"%.*f",locale,precision,value);
#elif defined(__APPLE__)
    const auto locale=TLinkNativeTouchLocale();
    if(!locale)return false;
    const int count=snprintf_l(out,size,locale,"%.*f",precision,value);
#else
    // Portable non-Apple test hosts: honor the usual C numeric locale. Production
    // Darwin and Windows test paths above use an explicit immutable locale.
    const int count=std::snprintf(out,size,"%.*f",precision,value);
#endif
    return count>0&&size_t(count)<size;
}
inline double TLinkNativeTouchJSCoordinate(double value) {
    if(!std::isfinite(value))return value;
    char text[384];if(!TLinkNativeTouchDecimal(text,sizeof(text),2,value))return NAN;
#ifdef _WIN32
    const auto locale=TLinkNativeTouchLocale();
    return locale?double(_strtof_l(text,nullptr,locale)):NAN;
#elif defined(__APPLE__)
    const auto locale=TLinkNativeTouchLocale();
    return locale?double(strtof_l(text,nullptr,locale)):NAN;
#else
    return double(std::strtof(text,nullptr));
#endif
}
inline int TLinkNativeTouchJSDuration(double value) {
    if(!std::isfinite(value))return -1;
    value=value<0?0:(value>60000?60000:value);
    char text[16];if(!TLinkNativeTouchDecimal(text,sizeof(text),0,value))return -1;
    return int(std::strtol(text,nullptr,10));
}
#endif
