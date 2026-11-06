#include "../shared/TLinkIndicatorPresentation.h"
#include <limits>
#include <random>
static void presentationCases(){
    using namespace TLinkIndicatorPresentation;
    Slots<20> slots;Slots<20>::Ticket ticket;
    assert(!slots.move(-1,Point())&&!slots.move(20,Point())&&!slots.peek(INT_MAX,ticket));
    for(int index=0;index<20;++index)slots.show(index,Point());
    for(unsigned n=0;n<100000;++n){int index=int(n%20);assert(slots.move(index,Point(n+1,index,.01)));}
    unsigned updates=0;
    for(int index=0;index<20;++index){assert(slots.peek(index,ticket));assert(ticket.point.x==99981+index);assert(slots.complete(index,ticket));++updates;}
    assert(updates==20&&!slots.pending());
    slots.move(0,Point(2,3,.01));assert(slots.peek(0,ticket));
    slots.move(0,Point(4,5,.01));assert(!slots.complete(0,ticket));
    assert(slots.peek(0,ticket));slots.hide(0);slots.show(0,Point());assert(!slots.complete(0,ticket));
    slots.move(0,Point(4,5,.01));assert(slots.peek(0,ticket));
    slots.move(0,Point());assert(!slots.complete(0,ticket)&&!slots.pending());
    slots.move(0,Point(1,2,.01));assert(slots.peek(0,ticket));
    Slots<20>::Ticket retry;assert(slots.peek(0,retry)&&retry.version==ticket.version); // Failed UI leaves work retryable.
    slots.clear();assert(!slots.pending());
    slots.show(0,Point());assert(slots.move(0,Point(1,2,.01))&&slots.peek(0,ticket)&&slots.begin(0,ticket));
    assert(slots.move(0,Point())&&slots.peek(0,ticket)&&slots.begin(0,ticket)&&slots.complete(0,ticket));
    slots.clear();

    struct Oracle {bool active=false;Point rendered,latest;};std::array<Oracle,20> oracle{};
    std::mt19937 random(42);
    for(unsigned n=0;n<200000;++n){
        int index=int(random()%20);unsigned operation=random()%5;Point point(double(random()%1000)/10,double(random()%1000)/10,double(random()%10)/100);
        auto &expected=oracle[index];
        if(operation==0){slots.show(index,point);expected.active=true;expected.rendered=expected.latest=point;}
        else if(operation==1){slots.hide(index);expected.active=false;}
        else if(operation==2){slots.move(index,point);if(expected.active)expected.latest=point;}
        else if(operation==3){slots.clear();for(auto &item:oracle)item.active=false;}
        else{
            for(int i=0;i<20;++i){auto &item=oracle[i];bool pending=item.active&&!(item.latest==item.rendered);
                assert(slots.peek(i,ticket)==pending);
                if(pending){assert(ticket.point==item.latest&&slots.complete(i,ticket));item.rendered=item.latest;}
            }
        }
        bool pending=false;for(const auto &item:oracle)pending=pending||(item.active&&!(item.latest==item.rendered));
        assert(slots.pending()==pending);
    }
    int x=0,y=0;
    for(unsigned n=0;n<100000;++n){double a=(double(int(random()%200000))-100000)/40,b=(double(int(random()%200000))-100000)/40,s=1+double(random()%4);
        assert(Layout(Point(a,b,.01),s,1590,x,y)&&x==int(a*s)&&y==int(b*s));
    }
    assert(Layout(Point(INT_MIN,INT_MAX,0),1,1590,x,y)&&x==INT_MIN&&y==INT_MAX);
    assert(Layout(Point(-0.,0.,0),3,1590,x,y)&&x==0&&y==0);
    for(double bad:{std::numeric_limits<double>::quiet_NaN(),std::numeric_limits<double>::infinity(),-std::numeric_limits<double>::infinity()}){
        assert(!Layout(Point(bad,1,.01),1,1590,x,y));assert(!Layout(Point(1,bad,.01),1,1590,x,y));
        assert(!Layout(Point(1,1,bad),1,1590,x,y));assert(!Layout(Point(1,1,.01),bad,1590,x,y));
    }
    assert(!Layout(Point(1,1,-.01),1,1590,x,y)&&!Layout(Point(1,1,.01),0,1590,x,y));
    assert(!Layout(Point(double(INT_MAX)+1,0,0),1,1590,x,y)&&!Layout(Point(0,double(INT_MIN)-1,0),1,1590,x,y));
    assert(!Layout(Point(0,0,std::numeric_limits<double>::max()),1,1590,x,y));
    puts("Indicator presentation passed: 100k moves to 20 latest slots, stale/reentrant/retry tickets, 200k independent lifecycle oracle steps and 100k frozen label/finite-boundary plans.");
}
