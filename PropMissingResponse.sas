%let CurFile = %sysget(SAS_EXECFILEPATH);
%let CurPath = %substr( &CurFile, 1, %eval(%length(&CurFile)-
%sysfunc(indexc(%sysfunc(reverse(&CurFile)),\/))) );
*libname abc "C:\Codes"; 
*run;


libname abc "&CurPath/data"; run;

/* Read the dataset using above path/directory */

options nofmterr;
data _one; set abc.a1079pga;
weight=bmi*(ht/100)**2;
run;

data _t1; set _one;
if EFRSLT=. then R1=1;  /* If Response (EFRSLT) is missing 
then the missing indicator (R1) is 1 */
else R1=0;
run;

/* Following augments the data in observed and missing parts */
data _t2; set _t1;
if R1=1 then do;
	do i=0 to 4;  /* There are 4 categories */
		EFRSLT=i; output;
	end;
end;
else output;
drop i;
run;

/* Following initializes the weight variable */
data _t2; set _t2;
wgt=1;
run;

/*proc contents data=_t2;
run;*/

/*proc export data=_t2 DBMS=csv outfile="/home/xieb09/dataall_uniq.csv";
run;*/

/* Following extracts the initial parameter estimates 
from a logistic regression fit 
which will be used as starting points in the EM */
ods output ParameterEstimates=_est1_orig;
proc logistic data=_t2 ;
class LEG_SORT (param=ref ref='203');  /* LEG_SORT is treatment variable 
having two treatments 
having 203 as the placebo/reference */
class SEX (param=ref ref='1');
model EFRSLT=LEG_SORT AGEYR SEX weight ONSETAGE/link=logit;
/* Covariates: AGEYR SEX ONSETAGE */
output out=_out1 PREDPROBS=i;
run;

ods output ParameterEstimates=_est2_orig;
proc logistic data=_t2 ;
class LEG_SORT (param=ref ref='203');
class SEX (param=ref ref='1');
model R1 (event='1')=EFRSLT LEG_SORT AGEYR SEX ONSETAGE;
run;

*ods html close;  /* Closes the ODS output */
*ods listing close;
*ods noresults;

%macro em;
data _oldbeta;  /* _olddata is the parameter estimates 
from previous two logistic regressions */
	do i=1 to 17;
		oldestimate=1;
		output;
	end;
drop i;
run;

/* EM starts */
%let epsilon=1;
%do %while (&epsilon >0.01);
ods output ParameterEstimates=_est1;
proc logistic data=_t2 ;
class LEG_SORT (param=ref ref='203');
class SEX (param=ref ref='1');
model EFRSLT=LEG_SORT AGEYR SEX weight ONSETAGE/link=logit;
weight wgt;
output out=_out1 PREDPROBS=i;
run;

data _out1; set _out1;
 if EFRSLT=0 then phat1=IP_0;
 else if EFRSLT=1 then phat1=IP_1;
 else if EFRSLT=2 then phat1=IP_2;
 else if EFRSLT=3 then phat1=IP_3;
 else if EFRSLT=4 then phat1=IP_4;
  drop _from_ _into_ IP_0-IP_4;
run; 

ods output ParameterEstimates=_est2;
proc logistic data=_out1 ;
class LEG_SORT (param=ref ref='203');
class SEX (param=ref ref='1');
model R1 (event='1')=EFRSLT LEG_SORT AGEYR SEX /*BMI*/ ONSETAGE;
weight wgt;
output out=_out2 PREDPROBS=i;
run;

data _out3; set _out2;
if r1=0 then phat2_=IP_0;
else if r1=1 then phat2_=IP_1;
prod=phat1*phat2_;
run;

proc means data=_out3 noprint;
 var prod;
output out=_th sum=sum;
by SUBJID; run;

data _mrgall;
merge _th (in=a) _out3 (in=b);
by SUBJID ;
if a=b;
run;

data _t2; set _mrgall;
wgtnew=prod/sum;
drop wgt sum prod phat1 phat2_ ;
rename wgtnew=wgt;
run;

data _beta; set _est1 _est2; run;

data _combo;
merge _oldbeta _beta;
diff=abs(oldestimate-estimate);
run;

proc sql noprint;
select sum(diff) into:epsilon from _combo;
quit; run;

data _oldbeta (rename=(estimate=oldestimate)); set _beta;
keep estimate;
run;

data _t2; set _t2;
drop _TYPE_ _FREQ_ _FROM_ _INTO_ IP_0 IP_1;
run;

proc sql;
drop table WORK._OUT1;
drop table WORK._OUT2;
drop table WORK._OUT3;
drop table WORK._TH;
drop table WORK._BETA;
drop table WORK._COMBO;
quit;
%end;
%mend em;  /* End of EM */

%em;
