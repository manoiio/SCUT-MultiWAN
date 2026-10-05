function mdays(y,m) { if(m==2)return(y%4==0&&(y%100!=0||y%400==0))?29:28;return(m==4||m==6||m==9||m==11)?30:31 }
NR==1 {if(NF!=2||$1!="SCUT_HOLIDAY_V1"||$2!=year)bad=1;next}
NR==2 {if(NF!=2||$1!="SOURCE"||$2!~/^https:\/\/www\.gov\.cn\/zhengce\/(content|zhengceku)\/[0-9]+\/content_[0-9]+\.htm$/)bad=1;next}
{
 if(NF!=2||$1!~/^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/||($2!="H"&&$2!="W")||seen[$1]++)bad=1
 split($1,a,"-"); y=a[1]+0;m=a[2]+0;d=a[3]+0
 if(y<year-1||y>year+1||m<1||m>12||d<1||d>mdays(y,m))bad=1
 if($2=="H")h++;else w++
 if($1==day)kind=$2
}
END {if(bad||NR<3||h<20||h>50||w>20)exit 1; if(day!="")print kind}
