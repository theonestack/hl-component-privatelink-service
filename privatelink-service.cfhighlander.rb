CfhighlanderTemplate do

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', allowedValues: ['development','production'], isGlobal: true
    ComponentParam 'NetworkLoadBalancers', '', type: 'CommaDelimitedList'
    ComponentParam 'AcceptanceRequired', 'false', allowedValues: ['true', 'false']
    ComponentParam 'PrivateDnsName', '', type: 'String'
  end

end
