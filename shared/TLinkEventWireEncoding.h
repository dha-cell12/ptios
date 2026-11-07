#pragma once
#include <cstddef>
#include <cstdint>
#include <limits>

namespace TLinkEventWireEncoding {
inline bool Size(std::size_t bytes,std::size_t &wireBytes){
    const std::size_t maximum=std::numeric_limits<std::size_t>::max();
    const std::size_t groups=bytes/3;
    if(groups>(maximum-5)/4)return false;
    std::size_t total=5+groups*4;
    if(bytes%3){if(maximum-total<4)return false;total+=4;}
    wireBytes=total;return true;
}
// The caller owns separate immutable input and writable output spans. Refuse
// all invalid sizes/pointers before touching output; write exactly Size bytes.
inline bool Encode(const uint8_t *input,std::size_t bytes,uint8_t *output,std::size_t capacity){
    std::size_t size=0;
    if(!Size(bytes,size)||capacity<size||!output||(bytes&&!input))return false;
    static const char alphabet[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    output[0]='0';output[1]=';';output[2]=';';
    std::size_t i=0,out=3;
    while(bytes-i>=3){
        const uint32_t value=(uint32_t(input[i])<<16)|(uint32_t(input[i+1])<<8)|input[i+2];
        output[out++]=alphabet[(value>>18)&63];output[out++]=alphabet[(value>>12)&63];
        output[out++]=alphabet[(value>>6)&63];output[out++]=alphabet[value&63];i+=3;
    }
    if(bytes-i){
        const bool two=bytes-i==2;
        const uint32_t value=(uint32_t(input[i])<<16)|(two?(uint32_t(input[i+1])<<8):0);
        output[out++]=alphabet[(value>>18)&63];output[out++]=alphabet[(value>>12)&63];
        output[out++]=two?alphabet[(value>>6)&63]:'=';output[out++]='=';
    }
    output[out++]='\r';output[out]='\n';return true;
}
}
