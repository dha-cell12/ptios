// Frozen pre-C02b9 find_multi_point ROI/offset/pixel policy, baseline fc1b96a.
// Returns false only for coordinate conversion failure; no work accounting in the oracle.
static bool legacyFrameMulti(const uint8_t *bgra,int sw,int sh,size_t stride,double scale,
        const TLinkNativeFrameMultiRequest &r,int &foundX,int &foundY){
    foundX=foundY=-1;const bool point=r.colors.frame.pointCoord;
    const auto coord=[scale,point](double v,int &out){double p=point?v*scale:v;
        if(!std::isfinite(v)||(point&&(!std::isfinite(scale)||scale<=0||scale>16))||!std::isfinite(p)||p<double(INT_MIN)+1||p>double(INT_MAX)-1)return false;
        out=int(std::round(p));return true;
    };
    int x=0,y=0,w=0,h=0;if(!coord(r.x,x)||!coord(r.y,y)||!coord(r.width,w)||!coord(r.height,h))return false;
    x=std::max(0,std::min(x,sw-1));y=std::max(0,std::min(y,sh-1));
    if(w<=0||w>sw-x)w=sw-x;if(h<=0||h>sh-y)h=sh-y;
    auto points=r.colors.points;
    int64_t minDx=INT_MAX,minDy=INT_MAX,maxDx=INT_MIN,maxDy=INT_MIN;
    for(auto &p:points){int dx=0,dy=0;if(!coord(p.dx,dx)||!coord(p.dy,dy))return false;p.dx=dx;p.dy=dy;
        minDx=std::min(minDx,int64_t(dx));minDy=std::min(minDy,int64_t(dy));maxDx=std::max(maxDx,int64_t(dx));maxDy=std::max(maxDy,int64_t(dy));
    }
    const int64_t x0=std::max(int64_t(x),-minDx),y0=std::max(int64_t(y),-minDy);
    const int64_t x1=std::min(int64_t(x)+w-1,int64_t(sw)-1-maxDx),y1=std::min(int64_t(y)+h-1,int64_t(sh)-1-maxDy);
    for(int64_t ay=y0;ay<=y1;ay+=r.skip+1)for(int64_t ax=x0;ax<=x1;ax+=r.skip+1){bool same=true;
        for(const auto &p:points){const uint8_t *pixel=bgra+size_t(ay+p.dy)*stride+size_t(ax+p.dx)*4;
            const int dr=std::abs(int(pixel[2])-p.r),dg=std::abs(int(pixel[1])-p.g),db=std::abs(int(pixel[0])-p.b);
            same=r.colors.mode==1?(dr<=int(r.colors.tolerance)&&dg<=int(r.colors.tolerance)&&db<=int(r.colors.tolerance)):
                1.0-(double(dr)+dg+db)/(3.0*255.0)>=r.colors.tolerance;
            if(!same)break;
        }
        if(same){foundX=int(ax);foundY=int(ay);return true;}
    }
    return true;
}
