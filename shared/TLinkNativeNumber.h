#ifndef TLINK_NATIVE_NUMBER_H
#define TLINK_NATIVE_NUMBER_H
#include <cstdio>
#include <locale.h>
#ifdef __APPLE__
#include <xlocale.h>
#endif
// One immutable C numeric locale per process; no per-call locale creation.
#ifdef _WIN32
inline _locale_t TLinkNativeNumberLocale(){static _locale_t value=_create_locale(LC_NUMERIC,"C");return value;}
#elif defined(__APPLE__)
inline locale_t TLinkNativeNumberLocale(){static locale_t value=newlocale(LC_NUMERIC_MASK,"C",nullptr);return value;}
#endif
inline bool TLinkNativeDecimal(char *out,size_t size,int precision,double value) {
#ifdef _WIN32
    const auto locale=TLinkNativeNumberLocale();
    if(!locale)return false;
    const int count=_snprintf_s_l(out,size,_TRUNCATE,"%.*f",locale,precision,value);
#elif defined(__APPLE__)
    const auto locale=TLinkNativeNumberLocale();
    if(!locale)return false;
    const int count=snprintf_l(out,size,locale,"%.*f",precision,value);
#else
    // Portable non-Apple test hosts: honor the usual C numeric locale. Production
    // Darwin and Windows test paths above use an explicit immutable locale.
    const int count=std::snprintf(out,size,"%.*f",precision,value);
#endif
    return count>0&&size_t(count)<size;
}
#endif
