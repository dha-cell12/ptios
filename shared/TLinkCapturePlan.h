#pragma once
#include <atomic>
#include <cmath>
#include <cstddef>
#include <climits>
#include <cstring>
#include <limits>

namespace TLinkCapturePlan {
struct Key {
    size_t width=0,height=0,row=0,allocation=0;
    bool global=true,signedDimensions=false;
    Key()=default;
    Key(size_t w,size_t h,size_t r,size_t a,bool g,bool s)
        :width(w),height(h),row(r),allocation(a),global(g),signedDimensions(s){}
    bool operator==(const Key &other)const {
        return width==other.width&&height==other.height&&row==other.row&&allocation==other.allocation&&
            global==other.global&&signedDimensions==other.signedDimensions;
    }
};
inline bool Valid(const Key &key){
    return key.width&&key.height&&key.width<=INT_MAX&&key.height<=INT_MAX&&
        key.width<=std::numeric_limits<size_t>::max()/4&&key.row>=key.width*4&&
        key.height<=std::numeric_limits<size_t>::max()/key.row&&key.allocation==key.row*key.height;
}
inline bool Display(double width,double height,double scale,int &outWidth,int &outHeight){
    if(!std::isfinite(width)||!std::isfinite(height)||!std::isfinite(scale)||width<=0||height<=0||scale<=0)return false;
    double x=width*scale,y=height*scale;
    const double edge=static_cast<double>(INT_MAX)+0.5;
    if(!std::isfinite(x)||!std::isfinite(y)||x<0.5||y<0.5||x>=edge||y>=edge)return false;
    const int a=static_cast<int>(std::llround(x)),b=static_cast<int>(std::llround(y));
    outWidth=a<b?a:b;outHeight=a<b?b:a;return true;
}
inline bool Row(int width,int height,size_t aligned,Key &out){
    if(width<=0||height<=0||static_cast<size_t>(width)>std::numeric_limits<size_t>::max()/4)return false;
    const size_t minimum=static_cast<size_t>(width)*4;
    if(aligned<minimum){
        if(minimum>std::numeric_limits<size_t>::max()-127)return false;
        aligned=(minimum+127)&~size_t(127);
    }
    if(static_cast<size_t>(height)>std::numeric_limits<size_t>::max()/aligned)return false;
    out=Key(width,height,aligned,aligned*static_cast<size_t>(height),true,true);return true;
}
inline size_t MachineLength(const char *bytes,size_t capacity){
    if(!bytes||!capacity)return 0;
    const void *end=std::memchr(bytes,0,capacity);
    return end?static_cast<const char *>(end)-bytes:0;
}
class BoolMemo {
    std::atomic<int> value_{-1};
public:
    bool read(bool &value)const{int found=value_.load(std::memory_order_acquire);if(found<0)return false;value=found!=0;return true;}
    bool publish(bool value){int empty=-1;value_.compare_exchange_strong(empty,value?1:0,std::memory_order_acq_rel,std::memory_order_acquire);return value_.load(std::memory_order_acquire)!=0;}
};
}
