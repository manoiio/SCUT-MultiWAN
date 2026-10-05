# Parse only the verified annual mainland notice grammar; never guess dates.
function die() { bad=1 }
function mdays(y,m) { if(m==2)return (y%4==0 && (y%100!=0 || y%400==0))?29:28; return (m==4||m==6||m==9||m==11)?30:31 }
function valid(y,m,d) { return y>=year-1 && y<=year+1 && m>=1 && m<=12 && d>=1 && d<=mdays(y,m) }
function key(y,m,d) { return sprintf("%04d-%02d-%02d",y,m,d) }
function dateparts(s,y,m,    a,n) {
 gsub(/[年月日]/," ",s); n=split(s,a,/ +/)
 if(n==4 && a[4]=="")n=3; if(n==3 && a[3]=="")n=2; if(n==2 && a[2]=="")n=1
 if(n==3){DY=a[1]+0; DM=a[2]+0; DD=a[3]+0; EXPLICIT=1}
 else if(n==2){DY=y; DM=a[1]+0; DD=a[2]+0; EXPLICIT=0}
 else if(n==1){DY=y; DM=m; DD=a[1]+0; EXPLICIT=0}
 else {die();return 0}
 return valid(DY,DM,DD)
}
function put(y,m,d,kind,    k) { k=key(y,m,d); if(k in days){die();return}; days[k]=kind; if(kind=="H")holidays++; else workdays++ }
{ html=html $0 "\n" }
END {
 if(year !~ /^20[0-9][0-9]$/ || year+0<2026 || length(html)>262144)exit 1
 gsub(/<\/[pP][[:space:]]*>/,"\n",html); gsub(/<[^>]*>/,"",html)
 gsub(/&nbsp;|&#160;|&#12288;/,"",html)
 title=html; gsub(/[[:space:]]/,"",title)
 if(index(title,"国务院办公厅关于" year "年部分节假日安排的通知")==0)exit 1
 n=split(html,lines,"\n")
 for(i=1;i<=n;i++) {
  line=lines[i]; gsub(/[[:space:]]/,"",line)
  if(line !~ /^[一二三四五六七八九十]+、/)continue
  colon=index(line,"："); if(!colon){die();continue}
  name=substr(line,1,colon-1); sub(/^[一二三四五六七八九十]+、/,"",name)
  rest=name; for(j=1;j<=7;j++) {
   names[1]="元旦"; names[2]="春节"; names[3]="清明节"; names[4]="劳动节"; names[5]="端午节"; names[6]="中秋节"; names[7]="国庆节"
   if(index(name,names[j])){ if(seen[j]++)die(); gsub(names[j],"",rest) }
  }
  gsub(/、|和|与/,"",rest); if(rest!=""){die();continue}
  sections++
  line=substr(line,colon+length("："));
  while((lp=index(line,"（"))>0){rp=index(substr(line,lp),"）");if(!rp){die();break};line=substr(line,1,lp-1) substr(line,lp+rp-1+length("）"))}
  gsub(/\([^)]*\)/,"",line)
  if(!match(line,/放假(调休)?/)){die();continue}
  span=substr(line,1,RSTART-1); after=substr(line,RSTART+RLENGTH)
  declared=0
  if(match(after,/共[0-9]+天/)){ t=substr(after,RSTART+3,RLENGTH-6); declared=t+0 }
  else if(match(after,/^[0-9]+天/)){ t=substr(after,RSTART,RLENGTH-3); declared=t+0 }
  if(declared<1||declared>15){die();continue}
  pieces=split(span,range,"至"); if(pieces<1||pieces>2){die();continue}
  if(range[1] !~ /^([0-9]+年)?[0-9]+月[0-9]+日$/){die();continue}
  if(!dateparts(range[1],year+0,0)){die();continue}
  sy=DY; sm=DM; sd=DD; explicit_start=EXPLICIT
  if(pieces==2) {
   if(range[2] !~ /^([0-9]+年)?([0-9]+月)?[0-9]+日$/ || !dateparts(range[2],year+0,sm)){die();continue}
   ey=DY; em=DM; ed=DD
   if(!explicit_start && em<sm)sy=year-1
  } else {ey=sy; em=sm; ed=sd}
  if(!valid(sy,sm,sd)||!valid(ey,em,ed)||key(sy,sm,sd)>key(ey,em,ed)){die();continue}
  y=sy;m=sm;d=sd;count=0
  while(key(y,m,d)<=key(ey,em,ed) && count<16) {
   put(y,m,d,"H");count++;d++;if(d>mdays(y,m)){d=1;m++;if(m>12){m=1;y++}}
  }
  if(count!=declared)die()
  # Work dates must be explicit; holiday dates never include the later clause.
  if(index(after,"上班")) {
   stop=index(after,"上班"); work=substr(after,1,stop-1); dot=index(work,"。"); if(dot)work=substr(work,dot+3)
   while(match(work,/([0-9]+年)?[0-9]+月[0-9]+日/)) {
    prefix=substr(work,1,RSTART-1); gsub(/、|，|,/,"",prefix); if(prefix!="")die()
    token=substr(work,RSTART,RLENGTH)
    if(!dateparts(token,year+0,0))die(); else put(DY,DM,DD,"W")
    work=substr(work,RSTART+RLENGTH)
   }
   gsub(/、|，|,/,"",work); if(work!="")die()
  }
 }
 for(j=1;j<=7;j++)if(seen[j]!=1)die()
 if(sections<6||sections>7||holidays<20||holidays>50||workdays>20)die()
 if(bad)exit 1
 print "SCUT_HOLIDAY_V1 " year
 print "SOURCE " source
 for(k in days)print k " " days[k]
}
