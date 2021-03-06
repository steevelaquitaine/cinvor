% testChannels.m
%      usage: [avgTestResponse r2 classifyCorrTotal stimValVector predStimVal] = testChannels(instances,stimValues,channel, varargin)
%         by: justin gardner and taosheng liu
%       date: 07/25/14
%    purpose: Test channel response using the forward model proposed by Brouwer & Heeger (2009).
%             Input1: instances can be those returned from getInstances (see getInstances), should be
%             the test instance from an independent section of the data (i.e., not the ones
%             used to build the channel).
%             Input2: stimValues is a vector of stimulus value for each instance class
%             Input3: channel is a struct returned by buildChannels
%             If a list of ROIs is passed in as first argument, will test channels
%             in each ROI (note the recursive call at the beginning). 
%             Outputs are:
%             avgTestResponse: the average channel response to the test instances
%             r2: the r2 value for predicting voxel responses, different methods are used
%             classifyCorrTotal: the number of correct and total classifications using the channel response.
%             stimValVector: the actual stimulus value for each test instance
%             predStimVal: the predicted stimulus value for each test instance using the channel response

function [avgTestResponse r2 classifyCorrTotal stimValVector predStimVal] = testChannels(instances,stimVals,channel,varargin)

% classifier = [];
% check arguments
if any(nargin == [0])
  help testChannels
  return
end

% parse input arguments
getArgs(varargin,{'instanceFieldName=instance','channelFieldName=channel','verbose=0'});

if isfield(instances{1},instanceFieldName) && isfield(instances{1},'name')
  for iROI = 1:length(instances)
    if ~isfield(instances{iROI}.(instanceFieldName),'instances')
      disp(sprintf('(testChannels) No instances found in %s for %s',instanceFieldName,instances{iROI}.name));
    elseif ~isfield(channel{iROI},channelFieldName) 
      disp(sprintf('(testChannels) No %s field found in %s. In this case the second argument must be a list of ROIs with precomputed channels.',channelFieldName,instances{iROI}.name));
    else
      [avgTestResponse(iROI,:) r2(iROI) classifyCorrTotal(iROI,:) stimValVector(iROI,:) predStimVal(iROI,:)]= testChannels(instances{iROI}.(instanceFieldName).instances,stimVals,channel{iROI}.(channelFieldName));
    end
  end
  return
end

% preprocess instances, using the setting from the trained channel
instances = preprocessInstances(instances, channel);

instanceMatrix=[]; stimValVector=[]; %stimClassVec=[];
for istim=1:length(instances)
  stimValVector=[stimValVector, repmat(stimVals(istim),1,size(instances{istim},1))];
  instanceMatrix=[instanceMatrix; instances{istim}];
end

testChannelResponse=instanceMatrix*pinv(channel.channelWeights); 
avgTestResponse=getAverageChannelResponse(testChannelResponse, stimValVector, channel.channelPref, channel.span/2);


%Prediction/Identification: correlate channel response with the span response and
%find the max correlation, which is the predicted value for the stimulus
corrWithSpanResp=corr(testChannelResponse',channel.spanResponse');
[maxCorr whichStim]=max(corrWithSpanResp,[],2);
predStimVal=channel.spanValues(whichStim);
%now do the same trick but correlate it with ideal reponse so we can classify the stimulus label
corrWithIdealResp=corr(testChannelResponse',channel.idealStimResponse');
[maxCorr whichStim]=max(corrWithIdealResp,[],2);
classifiedStimval=channel.idealStimVals(whichStim);
classifyCorrTotal=[sum(classifiedStimval==stimValVector) length(stimValVector)];

%this part get predicted instance for each stim class 
for i=1:length(stimVals)
  idx=channel.idealStimVals==stimVals(i);
  thisResp=channel.idealStimResponse(idx,:);
%   predInstances(i,:)=thisResp*channel.channelWeights*max(avgTestResponse);
  predInstances(i,:)=thisResp*channel.channelWeights;
end
nclass=size(predInstances,1);
nvox=size(predInstances,2);
%Now calculate a r2 value for the actual test data
allTestInstance=[]; allPredInstance=[];
for i=1:nclass
  thisTestClass=instances{i}; 
  thisPredClass=repmat(predInstances(i,:),size(thisTestClass,1),1);
  allTestInstance=[allTestInstance; thisTestClass];
  allPredInstance=[allPredInstance; thisPredClass];
  thisClassSSR=0; thisClassSS=0;
  for j=1:size(thisTestClass,1) %loop through trials
    thisTestTrial=thisTestClass(j,:);
    sumOfSquaresResidual = sum((thisTestTrial-thisPredClass(j,:)).^2);
    sumOfSquares = sum((thisTestTrial-mean(thisTestTrial)).^2);
    thisR2(j)=1-sumOfSquaresResidual/sumOfSquares;

    thisClassSSR=thisClassSSR+sumOfSquaresResidual;
    thisClassSS=thisClassSS+sumOfSquares;    
  end
  r2.clAvg(i)=mean(thisR2);
  r2.clAcc(i)= 1-thisClassSSR/thisClassSS;
  %doing everything in a single shot
  thisTestClass=thisTestClass(:);
  thisPredClass=thisPredClass(:);
  ssr=sum((thisTestClass-thisPredClass).^2);
  ss=sum((thisTestClass-mean(thisTestClass)).^2);
  r2.clOneshot(i) =1-ssr/ss;
end
allTestInstance=allTestInstance(:);
allPredInstance=allPredInstance(:);
ssr=sum((allTestInstance-allPredInstance).^2);
ss=sum((allTestInstance-mean(allTestInstance)).^2);
r2.overall=1-ssr/ss;

%do it for each voxel
for i=1:nvox
  temp=cellfun(@(x) x(:,i),instances,'UniformOutput',false);
  thisTestVox=cell2mat(temp);
  thisPredVox=repmat(predInstances(:,i)', size(thisTestVox,1),1);
  thisVoxSSR=0; thisVoxSS=0;
  for j=1:size(thisTestVox, 1)
    thisTestTrial=thisTestVox(j,:);
    sumOfSquaresResidual = sum((thisTestTrial-thisPredVox(j,:)).^2);
    sumOfSquares = sum((thisTestTrial-mean(thisTestTrial)).^2);
    thisR2Vox(j)=1-sumOfSquaresResidual/sumOfSquares;

    thisVoxSSR=thisVoxSSR+sumOfSquaresResidual;
    thisVoxSS=thisVoxSS+sumOfSquares;   
  end
  r2.voxAvg(i)=mean(thisR2Vox);
  r2.voxAcc(i)= 1-thisVoxSSR/thisVoxSS;
  %doing everything in a single shot
  thisTestVox=thisTestVox(:);
  thisPredVox=thisPredVox(:);
  ssr=sum((thisTestVox-thisPredVox).^2);
  ss=sum((thisTestVox-mean(thisTestVox)).^2);
  r2.voxOneshot(i) =1-ssr/ss;   
end
return;

function avgChannelResponse=getAverageChannelResponse(testChannelResponse,stimValVector,channelPref,channelCenter)
if ~isequal(unique(stimValVector), channelPref)
  error('TSL:the current shift and average scheme is probably incorrect when channel preferences are different from the stimulus values');
end

centerIdx=find(channelPref==channelCenter);
if isempty(centerIdx)
  disp(['should have a channel centered on ', num2str(channelCenter)]);
  keyboard;
end
allStimResp=[];
for i=1:length(channelPref)
  theseRespIdx=stimValVector==channelPref(i);
  theseStimResp=testChannelResponse(theseRespIdx,:);
  allStimResp=[allStimResp; circshift(theseStimResp,[0 centerIdx-i])];
end
avgChannelResponse=mean(allStimResp,1);



