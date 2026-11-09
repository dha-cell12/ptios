import assert from 'node:assert/strict';
import vm from 'node:vm';
export function checkConsoleProducerJS(current,previous){
    const make=(prelude,admission)=>{
        const state={rows:[],admissions:0,allowed:true};
        const context=vm.createContext({_tlinkautoLog:(level,message)=>state.rows.push([level,message])});
        if(admission)context._tlinkautoLogCanAccept=()=>{++state.admissions;return state.allowed;};
        vm.runInContext(prelude,context);return {state,context};
    };
    const native=text=>{let count=Math.min(text.length,4096);if(count&&count<text.length&&text.charCodeAt(count-1)>=0xd800&&text.charCodeAt(count-1)<=0xdbff&&text.charCodeAt(count)>=0xdc00&&text.charCodeAt(count)<=0xdfff)--count;return text.slice(0,count);};
    const old=previous.map(code=>make(code,false)),now=make(current,true);
    const recipes=["[]","['',undefined,null,false,0,-0,NaN,Infinity]","['ảnh 测试 😀','a\\u0000b','x\\r\\ny']","[{n:1,a:[true,null,'ảnh']},/x/,function(){},Symbol('x')]","[12n,new Date(0)]","[(function(){var a={};a.self=a;return a;})()]","[{toJSON:function(){trace.push('json');return {x:7};}}]","[{toJSON:function(){trace.push('throw');throw Error('x');},toString:function(){trace.push('string');return 'fallback';}}]"];
    function run(target,script){target.state.rows=[];vm.runInContext('var trace=[];'+script,target.context);return {rows:target.state.rows.map(([l,m])=>[l,native(m)]),trace:JSON.stringify(vm.runInContext('trace',target.context))};}
    for(let n=0;n<10000;++n){
        const method=['log','info','warn','error'][n%4],args=recipes[n%recipes.length];
        const script=`console.${method}.apply(console,${args}.concat([${n}]));`;
        const actual=run(now,script);for(const before of old)assert.deepEqual(actual,run(before,script));
        assert.ok(now.state.rows.every(row=>row[1].length<=4097));
    }
    for(const length of [0,4095,4096,4097,4098,262144]){
        for(const script of [
            `console.log('x'.repeat(${length}),'😀','tail');`,
            `console.warn('x'.repeat(${length})+'😀');`,
            `console.error('x'.repeat(${length}),{toJSON:function(){trace.push('late-json');return 'suffix';}});`
        ]){const actual=run(now,script);for(const before of old)assert.deepEqual(actual,run(before,script));assert.ok(now.state.rows[0][1].length<=4097);}
    }
    const large="var values=Array(128).fill('x'.repeat(65536));console.log.apply(console,values);";
    const actual=run(now,large);for(const before of old)assert.deepEqual(actual,run(before,large));assert.equal(now.state.rows[0][1].length,4097);
    for(const script of [
        "console.log('x'.repeat(5000),{toJSON:function(){trace.push('last-json');throw Error('json');},toString:function(){trace.push('last-string');throw Error('string');}});",
        "JSON.stringify=function(v){trace.push('encode'+v);return {toString:function(){trace.push('string'+v);return 'custom'+v;}};};console.log(1,2,3);",
        "JSON.stringify=function(v){trace.push('encode'+v);return v===1?undefined:v===2?null:v===3?42:'tail';};console.log(1,2,3,4);"
    ]){
        const outcomes=[...previous,current].map(prelude=>{const target=make(prelude,true);let error='';try{run(target,script);}catch(e){error=e.message;}return {error,rows:target.state.rows.map(([l,m])=>[l,native(m)]),trace:JSON.stringify(vm.runInContext('trace',target.context))};});
        for(const value of outcomes.slice(1))assert.deepEqual(value,outcomes[0]);
    }
    const saturated=make(current,true);saturated.state.allowed=false;
    vm.runInContext("var evaluations=0,conversions=0;function value(){++evaluations;return {toJSON:function(){++conversions;return 'x';}};}for(var i=0;i<1000;++i)console.log(value());",saturated.context);
    assert.equal(saturated.state.admissions,1000);assert.equal(saturated.state.rows.length,0);
    assert.equal(vm.runInContext('evaluations',saturated.context),1000);assert.equal(vm.runInContext('conversions',saturated.context),0);
    saturated.state.allowed=true;vm.runInContext("console.info(value());",saturated.context);assert.equal(saturated.state.rows.length,1);assert.equal(vm.runInContext('conversions',saturated.context),1);
    const fast=make(current,true);fast.state.allowed=false;vm.runInContext("console.log('short');console.info();console.warn('x'.repeat(4097));",fast.context);
    assert.equal(fast.state.admissions,0);assert.equal(fast.state.rows.length,3);assert.equal(fast.state.rows[2][1].length,4097);
    const noGate=make(current,false);assert.deepEqual(run(noGate,"console.log('fallback',{a:1});"),run(old[0],"console.log('fallback',{a:1});"));
    const intrinsic=make(current,true);vm.runInContext("Array.prototype.map=function(){throw Error('map');};Array.prototype.join=function(){throw Error('join');};String.prototype.slice=function(){throw Error('slice');};console.log('x'.repeat(100000),1);",intrinsic.context);
    assert.equal(intrinsic.state.rows[0][1].length,4097);
    for(const method of ['log','info','warn','error'])assert.equal(vm.runInContext(`console.${method}('return')`,now.context),undefined);
    console.log('Console producer JS passed: 10k frozen root/helper cases, exact 4095/4096/4097 Unicode prefixes, 8-MiB aggregate to 4097-unit transfer, all admitted argument effects/late throws, exotic serializer coercion order, 1000 preflight refusals without formatting, recovery and missing-gate fallback.');
}
