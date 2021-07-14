CloudFormation do

  Resource('EndpointService') do
    Type 'AWS::EC2::VPCEndpointService'
    Property('NetworkLoadBalancerArns', Ref('NetworkLoadBalancers'))
    Property('AcceptanceRequired', Ref('AcceptanceRequired'))
  end

  EC2_VPCEndpointServicePermissions('EndpointServicePermissions') do
    ServiceId Ref('EndpointService')
    AllowedPrincipals allowed_principals
  end

  Output(:EndpointServiceName) {
    Value(FnSub("com.amazonaws.vpce.${AWS::Region}.${EndpointService}"))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-EndpointServiceName")
  }

  Condition(:PrivateDnsEnabled, FnNot(FnEquals(Ref('PrivateDnsName'), "")))

  Resource(:PrivateDns) {
    Condition :PrivateDnsEnabled
    Type "Custom::PrivateDns"
    Property 'ServiceToken', FnGetAtt('ccrPrivateDnsFunction', 'Arn')
    Property 'ServiceId', Ref('EndpointService')
    Property 'DnsName', Ref('PrivateDnsName')
  }

  Output(:DnsName) do
    Condition :PrivateDnsEnabled
    Value(FnGetAtt(:PrivateDns, 'DnsName'))
  end

  Output(:DomainVerificationName) do
    Condition :PrivateDnsEnabled
    Value(FnGetAtt(:PrivateDns, 'DomainVerificationName'))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-DomainVerificationName")
  end

  Output(:DomainVerificationValue) do
    Condition :PrivateDnsEnabled
    Value(FnGetAtt(:PrivateDns, 'DomainVerificationValue'))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-DomainVerificationValue")
  end

  if external_parameters[:dns_format]
    Route53_RecordSet(:PrivateDnsVerificationRecord) do
      Condition :PrivateDnsEnabled
      HostedZoneName FnSub("#{dns_format}.")
      Name FnJoin(".", [FnGetAtt(:PrivateDns, 'DomainVerificationName'), FnSub("#{dns_format}.")])
      Type 'TXT'
      ResourceRecords [FnGetAtt(:PrivateDns, 'DomainVerificationValue')]
      TTL '300'
    end
  end

  IAM_Role(:ccrPrivateDnsRole) {
    Condition :PrivateDnsEnabled
    AssumeRolePolicyDocument({
      Version: '2012-10-17',
      Statement: [
        {
          Effect: 'Allow',
          Principal: {
            Service: [
              'lambda.amazonaws.com'
            ]
          },
          Action: 'sts:AssumeRole'
        }
      ]
    })
    Path '/'
    Policies([
      {
        PolicyName: 'endpointServices',
        PolicyDocument: {
          Version: '2012-10-17',
          Statement: [
            {
              Effect: 'Allow',
              Action: [
                'ec2:DescribeVpcEndpointServiceConfigurations',
                'ec2:ModifyVpcEndpointServiceConfiguration'
              ],
              Resource: '*'
            },
            {
              Effect: 'Allow',
              Action: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              Resource: '*'
            }
          ]
        }
      }
    ])
  }

  Logs_LogGroup(:ccrPrivateDnsLogGroup) {
    Condition :PrivateDnsEnabled
    LogGroupName FnSub("/aws/lambda/${ccrPrivateDnsFunction}")
    RetentionInDays 30
  }

  Lambda_Function(:ccrPrivateDnsFunction) {
    Condition :PrivateDnsEnabled
    Code({
      ZipFile: <<~CODE
        import cfnresponse
        import boto3
        import logging
        logger = logging.getLogger(__name__)
        logger.setLevel(logging.INFO)
        def lambda_handler(event, context):
            try:
                logger.info(event)
                responseData = {}
                serviceId = event['ResourceProperties']['ServiceId']
                dnsName =   event['ResourceProperties']['DnsName']
                client = boto3.client('ec2')
                if event['RequestType'] in ['Create', 'Update']:
                    logger.info(event['RequestType'] + " Private Dns Name")
                    client.modify_vpc_endpoint_service_configuration(ServiceId=serviceId, PrivateDnsName=dnsName, RemovePrivateDnsName=False)
                    response = client.describe_vpc_endpoint_service_configurations(ServiceIds=[serviceId])
                    responseData['DnsName'] = event['ResourceProperties']['DnsName']
                    responseData['DomainVerificationName'] = response['ServiceConfigurations'][0]['PrivateDnsNameConfiguration']['Name']
                    responseData['DomainVerificationValue'] = '"' + response['ServiceConfigurations'][0]['PrivateDnsNameConfiguration']['Value'] + '"'
                elif event['RequestType'] == 'Delete':
                    response = client.describe_vpc_endpoint_service_configurations(ServiceIds=[serviceId])
                    if response['ServiceConfigurations'][0]['PrivateDnsName'] == dnsName:
                        logger.info("Remove Private Dns Name")
                        client.modify_vpc_endpoint_service_configuration(ServiceId=serviceId, RemovePrivateDnsName=True)
                cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData)
            except Exception as e:
                logger.error('Failed to update private dns name', exc_info=True)
                cfnresponse.send(event, context, cfnresponse.FAILED, {})
      CODE
    })
    Handler "index.lambda_handler"
    Runtime "python3.8"
    Role FnGetAtt(:ccrPrivateDnsRole, :Arn)
    Timeout 60
  }



end