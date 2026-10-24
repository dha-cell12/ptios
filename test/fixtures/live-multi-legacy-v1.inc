// Frozen pre-C02b12 planning/traversal: safe signed anchors and first match on full RGBA.
static void legacyLiveMulti(const uint8_t *rgba,int sw,int sh,const TLinkNativeColorMultiRequest &r,int &fx,int &fy){
    fx=fy=-1;int x=std::max(0,std::min(r.x,sw-1)),y=std::max(0,std::min(r.y,sh-1));
    int w=r.width<=0?sw-x:std::min(r.width,sw-x),h=r.height<=0?sh-y:std::min(r.height,sh-y);
    int64_t minX=INT_MAX,minY=INT_MAX,maxX=INT_MIN,maxY=INT_MIN;
    for(const auto &p:r.colors.points){minX=std::min(minX,int64_t(p.dx));minY=std::min(minY,int64_t(p.dy));maxX=std::max(maxX,int64_t(p.dx));maxY=std::max(maxY,int64_t(p.dy));}
    const int64_t x0=std::max(int64_t(x),-minX),y0=std::max(int64_t(y),-minY),x1=std::min(int64_t(x)+w-1,int64_t(sw)-1-maxX),y1=std::min(int64_t(y)+h-1,int64_t(sh)-1-maxY);
    for(int64_t ay=y0;ay<=y1;ay+=int64_t(r.skip)+1)for(int64_t ax=x0;ax<=x1;ax+=int64_t(r.skip)+1){bool match=true;
        for(const auto &p:r.colors.points){const uint8_t *pixel=rgba+(size_t(ay+p.dy)*sw+size_t(ax+p.dx))*4;
            if(!legacyColorMatch(pixel[0],pixel[1],pixel[2],p.r,p.g,p.b,r.colors.mode,r.colors.tolerance)){match=false;break;}}
        if(match){fx=int(ax);fy=int(ay);return;}
    }
}
