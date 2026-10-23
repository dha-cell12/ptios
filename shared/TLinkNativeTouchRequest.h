#ifndef TLINK_NATIVE_TOUCH_REQUEST_H
#define TLINK_NATIVE_TOUCH_REQUEST_H
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <vector>
#include <locale.h>
#ifdef __APPLE__
#include <xlocale.h>
#endif
// Numeric task boundary; the shared executor performs argument validation.
enum class TLinkNativeTouchKind { Tap, Swipe, Gesture, Zoom };
struct TLinkNativeGesturePoint {double x,y;};
struct TLinkNativeTouchRequest {
    TLinkNativeTouchKind kind=TLinkNativeTouchKind::Tap;
    double x1=0,y1=0,x2=0,y2=0;
    int durationMs=50,finger=0,steps=0,fingerCount=2;
    double startRadius=0,endRadius=0,angleDegrees=0;
    std::vector<TLinkNativeGesturePoint> points;
};
inline int TLinkNativeTouchTask(TLinkNativeTouchKind kind) {
    switch(kind){case TLinkNativeTouchKind::Tap:return 62;case TLinkNativeTouchKind::Swipe:return 63;case TLinkNativeTouchKind::Gesture:case TLinkNativeTouchKind::Zoom:return 64;}return 0;
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
inline double TLinkNativeTouchJSNumber(double value,bool narrow,size_t *encodedBytes=nullptr) {
    if(encodedBytes)*encodedBytes=0;
    if(!std::isfinite(value))return value;
    char text[384];if(!TLinkNativeTouchDecimal(text,sizeof(text),2,value))return NAN;
    if(encodedBytes)*encodedBytes=std::strlen(text);
#ifdef _WIN32
    const auto locale=TLinkNativeTouchLocale();if(!locale)return NAN;
    return narrow?double(_strtof_l(text,nullptr,locale)):_strtod_l(text,nullptr,locale);
#elif defined(__APPLE__)
    const auto locale=TLinkNativeTouchLocale();if(!locale)return NAN;
    return narrow?double(strtof_l(text,nullptr,locale)):strtod_l(text,nullptr,locale);
#else
    return narrow?double(std::strtof(text,nullptr)):std::strtod(text,nullptr);
#endif
}
inline double TLinkNativeTouchJSCoordinate(double value,size_t *encodedBytes=nullptr){return TLinkNativeTouchJSNumber(value,true,encodedBytes);}
inline double TLinkNativeTouchJSZoomNumber(double value){return TLinkNativeTouchJSNumber(value,false);}
inline size_t TLinkNativeTouchIntegerBytes(int value){
    uint32_t magnitude=value<0?0U-uint32_t(value):uint32_t(value);size_t bytes=value<0?2:1;
    while(magnitude>=10){magnitude/=10;++bytes;}return bytes;
}
inline bool TLinkNativeGestureInputFits(size_t pointBytes,int finger,int duration){
    const size_t overhead=6+TLinkNativeTouchIntegerBytes(finger)+TLinkNativeTouchIntegerBytes(duration);
    return pointBytes<=8192-overhead;
}
// ASCII object batches use the same 8192-character ingress cap as task 65.
// Saturation keeps size arithmetic bounded while later JS shape errors are checked.
class TLinkNativeBatchInputSize {
    size_t bytes_=2,count_=0;
public:
    void append(size_t commandBytes) {
        const size_t separator=count_++?2:0;
        if(bytes_>8192||commandBytes>8192-bytes_||separator>8192-bytes_-commandBytes)bytes_=8193;
        else bytes_+=commandBytes+separator;
    }
    bool fits()const{return bytes_<=8192;}
    size_t bytes()const{return bytes_;}
};
inline int TLinkNativeTouchJSDuration(double value,size_t *encodedBytes=nullptr) {
    if(encodedBytes)*encodedBytes=0;
    if(!std::isfinite(value))return -1;
    value=value<0?0:(value>60000?60000:value);
    char text[16];if(!TLinkNativeTouchDecimal(text,sizeof(text),0,value))return -1;
    if(encodedBytes)*encodedBytes=std::strlen(text);
    return int(std::strtol(text,nullptr,10));
}
#endif
