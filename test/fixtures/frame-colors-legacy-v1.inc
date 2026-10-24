// Frozen pre-C02b8 is_colors evaluation, baseline d6147de. Table parsing is tested separately.
static bool legacyFrameColors(const uint8_t *bgra,int sw,int sh,size_t stride,double scale,
        const std::vector<TLinkColorPoint> &points,bool pointCoord,int mode,double value){
    bool matched=true;
    for(const auto &pc:points){
        int x=INT_MIN,y=INT_MIN;
        TLinkFrameColorCoordinate(pc.dx,scale,pointCoord,x);TLinkFrameColorCoordinate(pc.dy,scale,pointCoord,y);
        if(x<0||y<0||x>=sw||y>=sh){matched=false;break;}
        const uint8_t *p=bgra+size_t(y)*stride+size_t(x)*4;
        const int dr=std::abs(int(p[2])-pc.r),dg=std::abs(int(p[1])-pc.g),db=std::abs(int(p[0])-pc.b);
        const bool same=mode==1?(dr<=int(value)&&dg<=int(value)&&db<=int(value)):
            (1.0-(double(dr)+double(dg)+double(db))/(3.0*255.0)>=value);
        if(!same){matched=false;break;}
    }
    return matched;
}
