# Flowseal winws .bat -> nfqws2 configuration (POSIX / BusyBox awk).
# Conversion only: never writes to the running nfqws2 installation.
# Based on Sxlenium/zapret-keenetic-converter (MIT); see LICENSE.
BEGIN {
    OUT=ENVIRON["FLOWSEAL_OUTPUT"]; GAMES=ENVIRON["FLOWSEAL_GAMES"]
    IFACE=ENVIRON["FLOWSEAL_INTERFACE"]; ALT_HEX=ENVIRON["FLOWSEAL_ALT_LUA_HEX"]
    ROOT="/opt/etc/nfqws2"
    PREFIX=ENVIRON["FLOWSEAL_STRATEGY_ID"]
    if(PREFIX=="")PREFIX="flowseal"
    if(PREFIX !~ /^[a-zA-Z0-9._-]+$/ || length(PREFIX)>96)fail("Invalid strategy identifier")
    if (OUT=="" || (GAMES!="yes" && GAMES!="no")) fail("Invalid converter environment")
    if(IFACE=="")IFACE="eth3"
    if(IFACE !~ /^[A-Za-z0-9._-]+$/)fail("Invalid WAN interface")
    n=split("filter-l3 filter-l7 filter-tcp filter-udp hostlist hostlist-domains hostlist-exclude hostlist-exclude-domains ipset ipset-exclude",a," ")
    for(i=1;i<=n;i++)PASS[a[i]]=1
    n=split("dpi-desync dpi-desync-any-protocol dpi-desync-badseq-increment dpi-desync-badack-increment dpi-desync-cutoff dpi-desync-fake-discord dpi-desync-fake-http dpi-desync-fake-quic dpi-desync-fake-stun dpi-desync-fake-tls dpi-desync-fake-tls-mod dpi-desync-fake-unknown dpi-desync-fake-unknown-udp dpi-desync-fakedsplit-pattern dpi-desync-fooling dpi-desync-hostfakesplit-midhost dpi-desync-hostfakesplit-mod dpi-desync-repeats dpi-desync-split-pos dpi-desync-split-seqovl dpi-desync-split-seqovl-pattern dpi-desync-ts-increment ip-id",a," ")
    for(i=1;i<=n;i++)CONSUMED[a[i]]=1
    TYPES["dpi-desync-fake-http"]="http_req"
    TYPES["dpi-desync-fake-tls"]="tls_client_hello"
    TYPES["dpi-desync-fake-quic"]="quic_initial"
    TYPES["dpi-desync-fake-discord"]="discord_ip_discovery"
    TYPES["dpi-desync-fake-stun"]="stun"
    TYPES["dpi-desync-fake-unknown"]="unknown"
    TYPES["dpi-desync-fake-unknown-udp"]="unknown"
    BUILTIN["http_req"]="fake_default_http"
    BUILTIN["tls_client_hello"]="fake_default_tls"
    BUILTIN["quic_initial"]="fake_default_quic"
    BUILTIN["discord_ip_discovery"]="0x00000000000000000000000000000000"
    BUILTIN["stun"]="0x00000000000000000000000000000000"
    BUILTIN["unknown"]="0x00000000000000000000000000000000"
}
function fail(message) {print "ERROR: " message > "/dev/stderr";bad=1;exit 2}
function diagnostic(level,code,message,p) {
    print level "\t" code "\t" p "\t" message >> (OUT "/diagnostics.tsv")
    if(level=="warning") warnings++
}
function trim(s) {sub(/^[ \t\r\n]+/,"",s);sub(/[ \t\r\n]+$/,"",s);return s}
function resolve(value) {
    gsub(/%[Gg][Aa][Mm][Ee][Ff][Ii][Ll][Tt][Ee][Rr][Tt][Cc][Pp]%/,GAMES=="yes"?"1024-65535":"12",value)
    gsub(/%[Gg][Aa][Mm][Ee][Ff][Ii][Ll][Tt][Ee][Rr][Uu][Dd][Pp]%/,GAMES=="yes"?"1024-65535":"12",value)
    return value
}
function parse(text, pos, rest, start, name, value, ch) {
    pos=1; current=1
    while(pos<=length(text)){
        rest=substr(text,pos);start=index(rest,"--")
        if(!start)break
        pos+=start+1;rest=substr(text,pos)
        if(!match(rest,/^[A-Za-z0-9][A-Za-z0-9-]*/)){pos++;continue}
        name=tolower(substr(rest,1,RLENGTH));pos+=RLENGTH;value=""
        if(substr(text,pos,1)=="="){
            pos++
            if(substr(text,pos,1)=="\""){
                pos++
                while(pos<=length(text)){
                    ch=substr(text,pos,1);pos++
                    if(ch=="\"")break
                    value=value ch
                }
            } else {
                while(pos<=length(text)){
                    ch=substr(text,pos,1)
                    if(ch==" "||ch=="\t"||ch=="\r"||ch=="\n")break
                    value=value ch;pos++
                }
                sub(/\^+$/,"",value)
            }
        }
        if(name=="new"){
            if(size[current]>0)current++
            continue
        }
        if(name ~ /^wf-/ && !has_profile)continue
        has_profile=1
        ++size[current];opt[current,size[current]]=name;val[current,size[current]]=resolve(value)
    }
    count=current
    if(size[current]==0)count--
}
function get(p,name,default_val, i,result) {
    result=default_val
    for(i=1;i<=size[p];i++)if(opt[p,i]==name)result=val[p,i]
    return result
}
function only_disabled_game(p,i,key,found) {
    found=0
    for(i=1;i<=size[p];i++){
        key=opt[p,i]
        if(key=="filter-tcp"||key=="filter-udp"){
            found=1
            if(val[p,i]!="12")return 0
        }
    }
    return found
}
function append(p,arg) {
    if(arg!="")converted[p,++converted_count[p]]=arg
}
function collect_ports(value,transport,n,parts,i,port,key){
    n=split(value,parts,",")
    for(i=1;i<=n;i++){
        port=trim(parts[i])
        if(port==""||port=="12"||index(port,"%"))continue
        if(port !~ /^[0-9]+([-:][0-9]+)?$/){
            diagnostic("warning","invalid-port","Invalid " transport " port: " port,0)
            continue
        }
        key=transport SUBSEP port
        if(!(key in ports)){ports[key]=1;port_item[transport,++port_count[transport]]=port}
    }
}
function port_list(t,i,j,temp,a,b,result,slots){
    for(i=1;i<=port_count[t];i++)for(j=i+1;j<=port_count[t];j++){
        a=port_item[t,i];b=port_item[t,j]
        if((a+0)>(b+0)||((a+0)==(b+0)&&a>b)){
            port_item[t,i]=b;port_item[t,j]=a
        }
    }
    result="";slots=0
    for(i=1;i<=port_count[t];i++){
        temp=port_item[t,i];gsub(/-/,":",temp)
        result=result (result!=""?",":"") temp
        slots+=(index(temp,":")?2:1)
    }
    if(slots>15)diagnostic("warning","multiport-limit",t "_PORTS has " slots " multiport slots (maximum 15)",0)
    return result
}
function filename(raw,s,name){
    if(raw ~ /(^|[\\\/])\.\.([\\\/]|$)/)fail("Unsafe file reference: " raw)
    s=raw;gsub(/\\/,"/",s)
    sub(/^%[Ll][Ii][Ss][Tt][Ss]%/,"",s)
    sub(/^%[Bb][Ii][Nn]%/,"",s)
    sub(/^.*\//,"",s);name=s
    if(name==""||name !~ /^[A-Za-z0-9._-]+$/)fail("Invalid file name: " raw)
    return name
}
function list_ref(raw,p,name,dest){
    name=filename(raw)
    if(name=="list-general.txt"||name=="list-general-user.txt")
        return ROOT "/lists/user.list"
    if(name=="list-exclude.txt"||name=="list-exclude-user.txt")
        return ROOT "/lists/exclude.list"
    if(name=="ipset-all.txt")return ROOT "/lists/ipset.list"
    if(name=="ipset-exclude.txt"||name=="ipset-exclude-user.txt")
        return ROOT "/lists/ipset_exclude.list"
    dest=name;sub(/\.txt$/,"",dest);dest=PREFIX "-" dest ".list"
    if(!(dest in lists_added)){
        print name "\t" dest >> (OUT "/lists.manifest")
        lists_added[dest]=1
    }
    diagnostic("info","separate-list","Separate Flowseal list required: " name,p)
    return ROOT "/lists/" dest
}
function blob_ref(raw,p,name,id,stem){
    if(raw=="!")return "fake_default_tls"
    if(raw ~ /^0x[0-9A-Fa-f]+$/||raw=="fake_default_tls"||raw=="fake_default_http"||raw=="fake_default_quic")return raw
    name=filename(raw)
    if(name in blob_ids)return blob_ids[name]
    id=name;sub(/\.[^.]+$/,"",id)
    gsub(/[^A-Za-z0-9_]/,"_",id);id=tolower(id);gsub(/^_+|_+$/,"",id)
    if(id=="")id="blob"
    stem=id
    while(id in used_ids)id=stem "_" ++suffix[stem]
    used_ids[id]=1;blob_ids[name]=id
    blob_order[++blob_count]=name;blob_names[name]=id
    return id
}
function fooled(p,repeat,i,n,items,mode,result,seq,ack,ip){
    result="";n=split(get(p,"dpi-desync-fooling",""),items,",")
    for(i=1;i<=n;i++){
        mode=trim(items[i])
        if(mode=="ts")result=result ":tcp_ts=" get(p,"dpi-desync-ts-increment","-600000")
        else if(mode=="badseq"){
            seq=get(p,"dpi-desync-badseq-increment","-10000")
            ack=get(p,"dpi-desync-badack-increment","-66000")
            if(seq!="0")result=result ":tcp_seq=" seq
            result=result ":tcp_ack=" ack ":tcp_ts_up"
        } else if(mode=="md5sig")result=result ":tcp_md5"
        else if(mode=="badsum")result=result ":badsum"
    }
    ip=get(p,"ip-id","");if(ip!="")result=result ":ip_id=" ip
    if(repeat){ip=get(p,"dpi-desync-repeats","");if(ip!="")result=result ":repeats=" ip}
    return result
}
function infer_payload(p,any,result,l7,n,items,i,token,tcp,udp){
    if(any)return "all"
    result="";l7=get(p,"filter-l7","")
    if(l7!=""){
        n=split(l7,items,",")
        for(i=1;i<=n;i++){
            token=trim(items[i])
            if(token=="http")result=result ",http_req"
            else if(token=="tls")result=result ",tls_client_hello"
            else if(token=="quic")result=result ",quic_initial"
            else if(token=="discord")result=result ",discord_ip_discovery"
            else if(token=="stun")result=result ",stun"
            else if(token=="wireguard")result=result ",wireguard_initiation,wireguard_response,wireguard_cookie"
            else if(token=="mtproto")result=result ",mtproto_initial"
            else if(token=="unknown")result=result ",unknown"
        }
    }
    if(result==""){
        tcp=get(p,"filter-tcp","");udp=get(p,"filter-udp","")
        if(tcp!=""){
            if(index(tcp,"443"))result=result ",tls_client_hello"
            if(index("," tcp ",",",80,"))result=result ",http_req"
            if(result=="")result=",tls_client_hello"
        } else if(udp!=""){
            for(i=1;i<=size[p];i++)if(opt[p,i] in TYPES)result=result "," TYPES[opt[p,i]]
        }
    }
    if(result=="")result=",known"
    sub(/^,/,"",result)
    n=split(result,items,",");result=""
    for(i=1;i<=n;i++){
        token=items[i]
        if(!(token in seen_payload)){
            result=result (result!=""?",":"") token
            seen_payload[token]=1
        }
    }
    for(token in seen_payload)delete seen_payload[token]
    return result
}
function translate(p,i,key,value,any,cut,modes,n,j,mode,payload,spec_count,curmod,lasttls,types,raws,mods,idx,parts,builtin,fake_n,args,blob,fn,common,pos,seq,pattern,mod,alt,mid,part_count){
    if(only_disabled_game(p)){
        diagnostic("info","game-profile-skipped","Game profile skipped",p)
        return
    }
    for(i=1;i<=size[p];i++){
        key=opt[p,i];value=val[p,i]
        if(PASS[key]){
            if(value==""){
                diagnostic("warning","missing-value","Missing value for --" key,p);continue
            }
            if(key=="hostlist"||key=="hostlist-exclude"||key=="ipset"||key=="ipset-exclude")
                value=list_ref(value,p)
            append(p,"--" key "=" value)
        }
        if(key=="filter-tcp")collect_ports(value,"TCP")
        if(key=="filter-udp")collect_ports(value,"UDP")
    }
    cut=get(p,"dpi-desync-cutoff","")
    if(cut!="")append(p,"--out-range=-" cut)
    any=(get(p,"dpi-desync-any-protocol","0")!=""&&get(p,"dpi-desync-any-protocol","0")!="0")
    payload=infer_payload(p,any)
    value=get(p,"dpi-desync","")
    if(value==""){diagnostic("warning","no-strategy","No dpi-desync parameter",p);return}
    spec_count=0;curmod="";lasttls=0
    for(i=1;i<=size[p];i++){
        key=opt[p,i];value=val[p,i]
        if(key=="dpi-desync-fake-tls-mod"){
            curmod=value;if(lasttls)mods[lasttls]=value
        } else if(key in TYPES&&value!=""){
            ++spec_count;types[spec_count]=TYPES[key];raws[spec_count]=value
            mods[spec_count]=(key=="dpi-desync-fake-tls"?curmod:"")
            if(key=="dpi-desync-fake-tls")lasttls=spec_count
        }
    }
    n=split(value,modes,",")
    # value now holds the last visited option; use the dpi-desync value.
    n=split(get(p,"dpi-desync",""),modes,",")
    for(j=1;j<=n;j++){
        mode=trim(modes[j])
        if(mode=="fake"){
            fake_n=spec_count
            if(fake_n==0){
                idx=split(payload,parts,",")
                for(i=1;i<=idx;i++)if(parts[i]!="all"&&parts[i]!="known"){
                    ++fake_n;types[fake_n]=parts[i]
                    raws[fake_n]=(parts[i] in BUILTIN?BUILTIN[parts[i]]:"0x00")
                    mods[fake_n]=get(p,"dpi-desync-fake-tls-mod","")
                }
                if(fake_n==0){
                    fake_n=1;types[1]="known";raws[1]="0x00";mods[1]=""
                }
            }
            for(i=1;i<=fake_n;i++){
                append(p,"--payload=" types[i])
                blob=blob_ref(raws[i],p)
                args="fake:blob=" blob fooled(p,1)
                if(types[i]=="tls_client_hello"&&mods[i]!=""&&mods[i]!="none")
                    args=args ":tls_mod=" mods[i]
                append(p,"--lua-desync=" args)
            }
        } else if(mode=="syndata"){
            append(p,"--payload=empty");append(p,"--lua-desync=syndata")
        } else if(mode=="multisplit"||mode=="multidisorder"||mode=="fakedsplit"||mode=="fakeddisorder"){
            append(p,"--payload=" payload)
            fn=(mode=="multidisorder"?"multidisorder_legacy":mode)
            args=fn
            pos=get(p,"dpi-desync-split-pos","")
            seq=get(p,"dpi-desync-split-seqovl","")
            pattern=get(p,"dpi-desync-split-seqovl-pattern","")
            if(pos!="")args=args ":pos=" pos
            if(seq!="")args=args ":seqovl=" seq
            if(pattern!="")args=args ":seqovl_pattern=" blob_ref(pattern,p)
            if(mode=="fakedsplit"||mode=="fakeddisorder"){
                pattern=get(p,"dpi-desync-fakedsplit-pattern","")
                if(pattern!="")args=args ":pattern=" blob_ref(pattern,p)
            }
            common=fooled(p,mode=="fakedsplit"||mode=="fakeddisorder")
            if(mode=="multisplit"||mode=="multidisorder"){
                part_count=split(common,parts,":");common=""
                for(idx=1;idx<=part_count;idx++)
                    if(parts[idx] ~ /^ip_id=/||parts[idx]=="tcp_ts_up")common=common ":" parts[idx]
            }
            append(p,"--lua-desync=" args common)
        } else if(mode=="hostfakesplit"){
            append(p,"--payload=" payload)
            args="";alt=0;mod=get(p,"dpi-desync-hostfakesplit-mod","")
            idx=split(mod,parts,",")
            for(i=1;i<=idx;i++){
                value=trim(parts[i])
                if(value ~ /^host=/)args=args ":" value
                else if(value=="altorder=1")alt=1
                else if(value=="altorder=0")alt=0
                else if(value!=""&&value!="none")fail("Unsupported hostfakesplit modifier: " value)
            }
            mid=get(p,"dpi-desync-hostfakesplit-midhost","")
            if(mid!="")args=args ":midhost=" mid
            if(alt){
                requires_alt=1;fn="zk_hostfakesplit_alt1"
                diagnostic("info","hostfakesplit-altorder","Custom Lua function for altorder=1",p)
            } else fn="hostfakesplit"
            append(p,"--lua-desync=" fn args fooled(p,1))
        } else if(mode!="")diagnostic("warning","unsupported-mode","Skipped dpi-desync=" mode,p)
    }
    for(i=1;i<=size[p];i++){
        key=opt[p,i]
        if(!PASS[key]&&!CONSUMED[key]&&key!="wf-tcp"&&key!="wf-udp")
            diagnostic("warning","unsupported-option","Skipped --" key,p)
    }
}
function escape_config(s, i,c,escaped,q){
    escaped="";q=sprintf("%c",96)
    for(i=1;i<=length(s);i++){
        c=substr(s,i,1)
        if(c=="\\"||c=="\""||c=="$"||c==q)escaped=escaped "\\" c
        else escaped=escaped c
    }
    return escaped
}
function write_assignment(name,which,file, i,j,k,text,line){
    text=""
    if(which=="base"){
        for(i=1;i<=base_count;i++){
            line=base[i]
            text=text (text!=""?"\n                 ":"") escape_config(line)
        }
    } else if(which=="final"){
        for(i=1;i<=converted_count[last];i++){
            line=converted[last,i]
            text=text (text!=""?"\n                 ":"") escape_config(line)
        }
    } else if(which=="custom"){
        for(j=1;j<last;j++){
            if(j>1)text=text (text!=""?"\n                 ":"") "--new"
            for(i=1;i<=converted_count[j];i++){
                line=converted[j,i]
                text=text (text!=""?"\n                 ":"") escape_config(line)
            }
        }
    }
    print name "=\"" text "\"" >> file
}
function render(file,i,name,line){
    print "# Generated by KeenUtils Flowseal converter (Shell + AWK)" > file
    print "# SAVED ONLY: not validated against the running nfqws2!" >> file
    print "ISP_INTERFACE=\047" IFACE "\047" >> file
    base[++base_count]="--lua-init=@" ROOT "/lua/zapret-lib.lua"
    base[++base_count]="--lua-init=@" ROOT "/lua/zapret-antidpi.lua"
    for(i=1;i<=blob_count;i++){
        name=blob_order[i]
        base[++base_count]="--blob=" blob_names[name] ":@" ROOT "/blobs/" PREFIX "-" name
        print name "\t" PREFIX "-" name "\t" blob_names[name] >> (OUT "/blobs.manifest")
    }
    if(requires_alt){
        if(ALT_HEX=="")fail("Lua source for altorder=1 missing")
        base[++base_count]="--lua-init=assert(load(((\"" ALT_HEX "\"):gsub(\"..\",function(cc)return(string.char(tonumber(cc,16)))end))))()"
    }
    write_assignment("NFQWS_BASE_ARGS","base",file)
    write_assignment("NFQWS_ARGS","final",file)
    print "NFQWS_ARGS_QUIC=\"\"" >> file
    print "NFQWS_ARGS_UDP=\"\"" >> file
    print "NFQWS_EXTRA_ARGS=\"\"" >> file
    print "NFQWS_ARGS_IPSET=\"\"" >> file
    write_assignment("NFQWS_ARGS_CUSTOM","custom",file)
    print "IPV6_ENABLED=1" >> file
    print "TCP_PORTS=" port_list("TCP") >> file
    print "UDP_PORTS=" port_list("UDP") >> file
    print "POLICY_NAME=\047nfqws\047" >> file
    print "POLICY_EXCLUDE=0" >> file
    print "LOG_LEVEL=0" >> file
    print "LOG_DEBUG_PATH=\"@/opt/var/log/nfqws2-debug.log\"" >> file
    print "NFQUEUE_NUM=300" >> file
    print "USER=nobody" >> file
    print "CONFIG_VERSION=1" >> file
    close(file)
}
{
    line=$0;sub(/\r$/,"",line)
    if(!started){
        rest=tolower(line)
        if(match(rest,/winws(\.exe)?/)){
            started=1;line=substr(line,RSTART+RLENGTH)
        } else next
    }
    sub(/\^[ \t]*$/,"",line)
    source_command=source_command " " line
}
END {
    if(bad)exit 2
    if(!started)fail("No winws.exe invocation found")
    parse(source_command)
    if(count<1)fail("No Flowseal profiles found")
    source_count=count
    for(p=1;p<=count;p++){
        if(only_disabled_game(p)){
            diagnostic("info","game-profile-skipped","Game profile skipped",p)
            continue
        }
        translate(p)
        if(converted_count[p]>0){
            target=++last
            if(target!=p){
                for(i=1;i<=converted_count[p];i++)converted[target,i]=converted[p,i]
                converted_count[target]=converted_count[p]
            }
        }
    }
    if(last<1)fail("No usable profiles after conversion")
    render(OUT "/nfqws2.conf")
    print "PROFILES_READ=" source_count > (OUT "/stats.txt")
    print "PROFILES_WRITTEN=" last >> (OUT "/stats.txt")
    print "WARNINGS=" warnings+0 >> (OUT "/stats.txt")
    print "ALTORDER=" requires_alt+0 >> (OUT "/stats.txt")
}