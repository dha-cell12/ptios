#pragma once

namespace TLinkCaptureOwnership {
template<class Ref,class Drop>
class Scoped {
    Ref value_;Drop drop_;
public:
    Scoped(Ref value,Drop drop):value_(value),drop_(drop){}
    ~Scoped(){if(value_)drop_(value_);}
    Scoped(const Scoped &)=delete;Scoped &operator=(const Scoped &)=delete;
    Ref get()const{return value_;}
    Ref release(){Ref value=value_;value_=Ref();return value;}
    void reset(Ref value){if(value_)drop_(value_);value_=value;}
};
template<class API>
typename API::Image Fresh(typename API::Surface surface,API &api){
    using Image=typename API::Image;
    if(!surface)return Image();
    struct Owner {
        typename API::Surface surface;API &api;bool locked;
        ~Owner(){if(locked)api.unlock(surface);api.dropSurface(surface);}
    } owner{surface,api,false};
    if(!api.lock(surface))return Image();
    owner.locked=true;
    auto drop=[&](Image value){api.dropImage(value);};
    Scoped<Image,decltype(drop)> image(Image(),drop);
    api.render(surface);image.reset(api.createImage(surface));
    if(!image.get()||!api.validImage(image.get()))return Image();
    if(api.rotates())image.reset(api.rotate(image.get()));
    owner.locked=false; // Never repeat an attempted explicit unlock.
    if(!api.unlock(surface))return Image();
    return image.release();
}
}
