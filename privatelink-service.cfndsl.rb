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

end