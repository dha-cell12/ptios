#include "../shared/TLinkTextTail.h"
#include <random>
#include <vector>
#include <stdexcept>
static bool historyTailDelimiter(char16_t c){return c==u'\r'||c==u'\n'||c==u'\v'||c==u'\f'||c==0x85||c==0x2028||c==0x2029;}
static void historyTextTailCases(){
    std::mt19937 random(731);
    for(unsigned n=0;n<100000;++n){
        std::u16string text;
        for(unsigned i=0;i<n%513;++i){
            const unsigned choice=random()%12;
            text+=choice==0?u'\n':choice==1?u'\r':choice==2?char16_t(0x2028):char16_t(random()%65536);
        }
        std::vector<std::u16string> split;size_t start=0;
        for(size_t i=0;i<text.size();++i)if(historyTailDelimiter(text[i])){split.push_back(text.substr(start,i-start));start=i+1;}
        split.push_back(text.substr(start));
        size_t calls=0;
        const auto plan=TLinkTextTail<50>::Build(text.size(),[&](size_t end){
            ++calls;while(end)if(historyTailDelimiter(text[--end]))return end;return SIZE_MAX;
        });
        const size_t offset=split.size()>50?split.size()-50:0;
        assert(plan.size()==split.size()-offset&&calls<=50);
        for(size_t i=0;i<plan.size();++i){const auto range=plan[i];assert(range.start<=text.size()&&range.length<=text.size()-range.start&&text.substr(range.start,range.length)==split[offset+i]);}
    }
    size_t calls=0;
    const auto dense=TLinkTextTail<50>::Build(262144,[&](size_t end){++calls;return end-1;});
    assert(dense.size()==50&&calls==50);
    for(size_t i=0;i<dense.size();++i)assert(dense[i].length==0);
    assert(TLinkTextTail<0>::Build(SIZE_MAX,[](size_t){assert(false);return size_t(0);}).size()==0);
    const auto empty=TLinkTextTail<1>::Build(0,[](size_t){assert(false);return size_t(0);});
    assert(empty.size()==1&&empty[0].start==0&&empty[0].length==0);
    const auto maximum=TLinkTextTail<1>::Build(SIZE_MAX,[](size_t){return SIZE_MAX;});
    assert(maximum.size()==1&&maximum[0].length==SIZE_MAX);
    assert(TLinkTextTail<50>::Build(3,[](size_t end){return end;}).size()==0);
    bool threw=false;try{(void)TLinkTextTail<50>::Build(1,[](size_t)->size_t{throw std::runtime_error("search");});}catch(const std::runtime_error &){threw=true;}
    assert(threw);
    puts("History text tail passed: 100k complete-split UTF16 oracles, empty/CRLF/NUL/Unicode/trailing separators, 50-range cap, 262145-to-50 dense component plan, size overflow and provider unwind.");
}
