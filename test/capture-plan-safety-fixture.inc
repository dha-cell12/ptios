static void capturePlanCases(){
    using namespace TLinkCapturePlan;
    for(unsigned n=0;n<100000;++n){
        const double x=1+n%4000+0.25,y=1+(n*73)%4000+0.75,scale=1+n%3;
        int width=-1,height=-1;assert(Display(x,y,scale,width,height));
        int a=(int)std::llround(x*scale),b=(int)std::llround(y*scale);
        assert(width==std::min(a,b)&&height==std::max(a,b));
        Key key;size_t minimum=(size_t)width*4;assert(Row(width,height,n%2?0:minimum+256,key));
        assert(Valid(key)&&key.row==(n%2?((minimum+127)&~size_t(127)):minimum+256));
        Key changed=key;assert(changed==key);changed.global=false;assert(!(changed==key));changed=key;changed.signedDimensions=false;assert(!(changed==key));
    }
    for(double bad:{0.0,-1.0,std::numeric_limits<double>::infinity(),std::numeric_limits<double>::quiet_NaN()}){
        int w=42,h=43;assert(!Display(bad,1,1,w,h)&&w==42&&h==43);assert(!Display(1,bad,1,w,h));assert(!Display(1,1,bad,w,h));
    }
    int w=0,h=0;assert(Display(.5,1,1,w,h)&&w==1&&h==1);assert(!Display(.49,1,1,w,h));
    assert(Display(INT_MAX+.49,1,1,w,h)&&h==INT_MAX);assert(!Display(INT_MAX+.5,1,1,w,h));
    Key sentinel(1,1,4,4,true,false),out=sentinel;assert(!Row(0,1,0,out)&&out==sentinel);
    assert(!Row(1,2,std::numeric_limits<size_t>::max(),out)&&out==sentinel);
    Key bad=sentinel;bad.row=0;assert(!Valid(bad));bad=sentinel;bad.allocation=3;assert(!Valid(bad));
    char machine[]={'i','P','a','d','8',0};assert(MachineLength(machine,sizeof(machine))==5&&MachineLength(machine,5)==0&&MachineLength(nullptr,4)==0);
    BoolMemo memo;bool value=false;assert(!memo.read(value));assert(memo.publish(true)&&memo.read(value)&&value);assert(memo.publish(false));
    for(unsigned race=0;race<32;++race){BoolMemo cold;std::vector<std::thread> threads;
        for(unsigned t=0;t<8;++t)threads.emplace_back([&]{for(unsigned n=0;n<10000;++n){bool found=false;if(!cold.read(found))found=cold.publish(true);assert(found);}});
        for(auto &thread:threads)thread.join();assert(cold.read(value)&&value);
    }
    std::puts("Capture preparation core passed: 100k frozen rounding/stride/allocation/key plans, axis/overflow/NaN/NUL boundaries and 32 x 8 x 10k atomic device-class reads.");
}
