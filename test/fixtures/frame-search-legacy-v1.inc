// Frozen pre-C02b7 search_single scan, baseline 650a4f4. Foundation formatting is tested separately.
static bool legacyFrameSearch(const uint8_t *bgra,int sw,int sh,size_t stride,double scale,
        const TLinkNativeFrameSearchRequest &r,TLinkNativeFrameSearchValue &out){
    int x=0,y=0,w=0,h=0;
    if(!TLinkFrameColorCoordinate(r.x,scale,r.frame.pointCoord,x)||!TLinkFrameColorCoordinate(r.y,scale,r.frame.pointCoord,y)||
       !TLinkFrameColorCoordinate(r.width,scale,r.frame.pointCoord,w)||!TLinkFrameColorCoordinate(r.height,scale,r.frame.pointCoord,h))return false;
    if(x<0)x=0;if(y<0)y=0;
    if(x>=sw)x=sw-1;if(y>=sh)y=sh-1;
    if(w<=0||w>sw-x)w=sw-x;if(h<=0||h>sh-y)h=sh-y;
    const int step=r.skip+1;
    out.x=out.y=out.red=out.green=out.blue=-1;
    for(int cy=0;cy<h;cy+=step){
        const uint8_t *row=bgra+size_t(y+cy)*stride;
        for(int cx=0;cx<w;cx+=step){
            const uint8_t *p=row+size_t(x+cx)*4;int b=p[0],g=p[1],red=p[2];
            if(red>=r.redMin&&red<=r.redMax&&g>=r.greenMin&&g<=r.greenMax&&b>=r.blueMin&&b<=r.blueMax){
                out.x=x+cx;out.y=y+cy;out.red=red;out.green=g;out.blue=b;return true;
            }
        }
    }
    return true;
}
