#pragma once
namespace TLinkAXSelectorMode {
enum class Kind {Contains,Exact,Prefix};
// Per-operation, single-owner state. Commit only after a provider returns.
class State {
    bool checked_=false,stable_=false,prepared_=false;
    Kind kind_=Kind::Contains;
public:
    template<class Check> bool stable(Check check){
        if(!checked_){const bool value=check();stable_=value;checked_=true;}
        return stable_;
    }
    template<class Equal> Kind kind(Equal equal){
        if(!prepared_){
            Kind value=Kind::Contains;
            if(equal(Kind::Exact))value=Kind::Exact;
            else if(equal(Kind::Prefix))value=Kind::Prefix;
            kind_=value;prepared_=true;
        }
        return kind_;
    }
};
}
