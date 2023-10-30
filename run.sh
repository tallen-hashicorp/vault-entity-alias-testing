#!/bin/bash

vault policy write base -<<EOF
path "secret/data/training_*" {
   capabilities = ["create", "read"]
}
EOF

vault policy write test -<<EOF
path "secret/data/test" {
   capabilities = [ "create", "read", "update", "delete" ]
}
EOF

vault policy write team-qa -<<EOF
path "secret/data/team-qa" {
   capabilities = [ "create", "read", "update", "delete" ]
}
EOF

vault policy list
echo "Policy setup complete, starting auth setup..."
sleep 5

vault auth enable -path="userpass-test" userpass
vault write auth/userpass-test/users/bob password="training" policies="test"
vault auth enable -path="userpass-qa" userpass
vault write auth/userpass-qa/users/bsmith password="training" policies="team-qa"
vault auth list -detailed
echo "Auth setup, starting aith aliasing..."
sleep 5

vault auth list -format=json | jq -r '.["userpass-test/"].accessor' > accessor_test.txt
vault auth list -format=json | jq -r '.["userpass-qa/"].accessor' > accessor_qa.txt
vault write -format=json identity/entity name="bob-smith" policies="base" \
     metadata=organization="ACME Inc." \
     metadata=team="QA" \
     | jq -r ".data.id" > entity_id.txt
vault write identity/entity-alias name="bob" \
     canonical_id=$(cat entity_id.txt) \
     mount_accessor=$(cat accessor_test.txt) \
     custom_metadata=account="Tester Account"
vault write identity/entity-alias name="bsmith" \
     canonical_id=$(cat entity_id.txt) \
     mount_accessor=$(cat accessor_qa.txt) \
     custom_metadata=account="QA Eng Account"
echo "Alias now setup, about to start testing this"
sleep 5

echo "-----------------------------"
vault login -format=json -method=userpass -path=userpass-test \
    username=bob password=training \
    | jq -r ".auth.client_token" > bob_token.txt
VAULT_TOKEN=$(cat bob_token.txt) vault kv put secret/test owner="bob"
echo ""
echo "bob: secret/data/training_test:"
VAULT_TOKEN=$(cat bob_token.txt) vault token capabilities secret/data/training_test
echo ""
echo "bob: secret/data/test:"
VAULT_TOKEN=$(cat bob_token.txt) vault token capabilities secret/data/test
echo ""
echo "bob: secret/data/team-qa:"
VAULT_TOKEN=$(cat bob_token.txt) vault token capabilities secret/data/team-qa
echo "-----------------------------"

vault login -format=json -method=userpass -path=userpass-qa \
    username=bsmith password=training \
    | jq -r ".auth.client_token" > bsmith_token.txt
echo ""
echo "bsmith: secret/data/training_test:"
VAULT_TOKEN=$(cat bsmith_token.txt) vault token capabilities secret/data/training_test
echo ""
echo "bsmith: secret/data/test:"
VAULT_TOKEN=$(cat bsmith_token.txt) vault token capabilities secret/data/test
echo ""
echo "bsmith: secret/data/team-qa:"
VAULT_TOKEN=$(cat bsmith_token.txt) vault token capabilities secret/data/team-qa
echo ""
echo "-----------------------------"
echo "All done, cleaning up files"

sleep 1

rm bob_token.txt
rm accessor_test.txt
rm accessor_qa.txt
rm entity_id.txt
unset VAULT_TOKEN