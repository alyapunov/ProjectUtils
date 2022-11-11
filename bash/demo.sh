#!/bin/bash

org="tarantool"
token=""
login=$USER
token_file=~/.token
since=""

usage() {
    echo ""
    echo "Fetch closed issues from project (V2) since some date"
    echo "Usage:"
    echo " $0 [options] <project number>"
    echo ""
    echo "Options:"
    echo " -l, --login          use GH login (default: $login)"
    echo " -t, --token          use GH token (default: see --token_file)"
    echo " -f, --token_file     take GH token from file (default: $token_file)"
    echo " -s, --since          date YYYY-MM-DDThh:mm:ss or any string that"
    echo "                       \`date -d <..>\` will take (default: -14 days)"
    echo " -h, --help           Show this help and exit"
    exit 0
}

error() {
   echo "$@" 1>&2
   exit 1
}

shortopts="l:t:f:s:h"
longopts="login:,token:,token_file:,since:,help"

opts=$(getopt --options "$shortopts" --long "$longopts" --name "$0" -- "$@")
eval set -- "$opts"

while true; do
    case "$1" in
        -l | --login ) login=$2; shift 2;;
        -t | --token ) token=$2; shift 2;;
        -f | --token_file ) token_file=$2; shift 2;;
        -s | --since ) since=$2; shift 2;;
        -h | --help ) usage; shift 1;;
        -- ) shift; break;;
        * ) error "Failed to parse options";;
    esac
done

if [[ -z "$token" ]]; then
    token=`cat $token_file 2>/dev/null`
fi

if [[ -z "$token" ]]; then
    error "Can't proceed without token"
fi

if ! [[ $# -eq 1 ]]; then
    usage
fi

proj_num=$1

if [[ -z "$since" ]]; then
    since=$(date -d "-14 days" +%Y-%m-%dT16:00:00)
fi

echo "Fetching closed since $since issues"

auth="${login}:${token}"

function gql {
    curl --request POST -u "${auth}" --url https://api.github.com/graphql \
         --data "{\"query\":\"query{$1}\"}" 2>/dev/null
}

proj_id=$(gql "organization(login: \\\"$org\\\") { \
                 projectV2(number: $proj_num) { \
                   id \
                 } \
               }" \
    | jq -r .data.organization.projectV2.id)

if [ "$proj_id" == "null" ]; then
    error "Unable to find project $proj_num. Shot yourself."
fi

end_cursor=""

function proj_query {
    after_items=""
    if ! [[ -z "$end_cursor" ]]; then
        after_items="after: \\\"$end_cursor\\\""
    fi
    q="node(id: \\\"$proj_id\\\") { \
         ... on ProjectV2 { \
           items(first: 20 $after_items) { \
             totalCount \
             pageInfo { \
               hasNextPage \
               endCursor \
             } \
             nodes { \
               type \
               id \
               fieldValues(first: 20) { \
                 totalCount
                 nodes { \
                   ... on ProjectV2ItemFieldTextValue { \
                     text \
                     field { \
                       ... on ProjectV2FieldCommon { name } \
                     } \
                   } \
                   ... on ProjectV2ItemFieldNumberValue { \
                     number \
                     field { \
                       ... on ProjectV2FieldCommon { name } \
                     } \
                   } \
                   ... on ProjectV2ItemFieldDateValue { \
                     date \
                     field { \
                       ... on ProjectV2FieldCommon { name } \
                     } \
                   } \
                   ... on ProjectV2ItemFieldSingleSelectValue { \
                     name \
                     field { \
                       ... on ProjectV2FieldCommon { name } \
                     } \
                   } \
                   ... on ProjectV2ItemFieldLabelValue { \
                     labels(first: 20) { \
                       totalCount \
                       nodes { name } \
                     } \
                     field { \
                       ... on ProjectV2FieldCommon { name } \
                     } \
                   } \
                   ... on ProjectV2ItemFieldRepositoryValue { \
                     repository { name } \
                     field { \
                       ... on ProjectV2FieldCommon { name } \
                     } \
                   } \
                   ... on ProjectV2ItemFieldIterationValue { \
                     title \
                     field { \
                       ... on ProjectV2FieldCommon { name } \
                     } \
                   } \
                   ... on ProjectV2ItemFieldMilestoneValue { \
                     milestone { title } \
                     field { \
                       ... on ProjectV2FieldCommon { name } \
                     } \
                   } \
                   ... on ProjectV2ItemFieldPullRequestValue { \
                     pullRequests { totalCount } \
                     field { \
                       ... on ProjectV2FieldCommon { name } \
                     } \
                   } \
                   ... on ProjectV2ItemFieldReviewerValue { \
                     reviewers { totalCount } \
                     field { \
                       ... on ProjectV2FieldCommon { name } \
                     } \
                   } \
                   ... on ProjectV2ItemFieldUserValue { \
                     users { totalCount } \
                     field { \
                       ... on ProjectV2FieldCommon { name } \
                     } \
                   } \
                 } \
               } \
               content { \
                 ... on DraftIssue { title body } \
                 ... on Issue { title url closed closedAt } \
                 ... on PullRequest { title url closed closedAt } \
               } \
             } \
           } \
         } \
       }"
    echo $q
}

old_folder=$(date -d "$since" +./%Y-%m-%d)
cur_folder=$(date +./%Y-%m-%d)

old_sp="??"
if [[ -d "$old_folder" ]]; then
    if [[ -f "$old_folder/total_sp.txt" ]]; then
        old_sp=$(cat "$old_folder/total_sp.txt")
    fi
fi

if ! [[ -d "$cur_folder" ]]; then
    mkdir "$cur_folder"
fi
if [[ -f "$cur_folder/issues.txt" ]]; then
    rm "$cur_folder/issues.txt"
fi
if [[ -f "$cur_folder/predemo.txt" ]]; then
    rm "$cur_folder/predemo.txt"
fi

total_sp=0
total_count=0
processed_count=0

echo -ne "%"
while true; do
    resp=$(gql "$(proj_query)")
    if [[ $total_count == 0 ]]; then
        total_count=$(echo "$resp" | jq .data.node.items.totalCount)
    fi
    has_next_page=$(echo "$resp" | jq .data.node.items.pageInfo.hasNextPage)
    end_cursor=$(echo "$resp" | jq -r .data.node.items.pageInfo.endCursor)

    count=$(echo "$resp" | jq .data.node.items.nodes | jq length)
    for (( i=0; i<$count; i++ )) ; do
        ((++processed_count))
        echo -ne "\rProcessing $processed_count of $total_count"

        doc=$(echo "$resp" | jq .data.node.items.nodes[$i])
        content_doc=$(echo "$doc" | jq -r .content)
        title=$(echo "$content_doc" | jq -r .title)
        url=$(echo "$content_doc" | jq -r .url)
        closed=$(echo "$content_doc" | jq -r .closed)
        closedAt=$(echo "$content_doc" | jq -r .closedAt)
        body=$(echo "$content_doc" | jq -r .body) #DraftIssue only

        if ! [[ $closed == true ]]; then
            continue
        fi
        if [[ $(date -d "$closedAt" +%s) -lt $(date -d "$since" +%s) ]]; then
            continue
        fi

        status="null"
        epic="null"
        type="null"
        estimate="null"
        labels=()
        has_epic_label=false

        labels_doc='{"labels":{"nodes":[]}}'
        field_count=$(echo "$doc" | jq .fieldValues.nodes | jq length)
        for (( j=0; j<$field_count; j++ )) ; do
            field_doc=$(echo "$doc" | jq .fieldValues.nodes[$j])
            field_name=$(echo "$field_doc" | jq -r .field.name)
            case "$field_name" in
                "Status" ) status=$(echo "$field_doc" | jq -r .name);;
                "Epic" ) epic=$(echo "$field_doc" | jq -r .name);;
                "Type" ) type=$(echo "$field_doc" | jq -r .name);;
                "Estimate" ) estimate=$(echo "$field_doc" | jq -r .number);;
                "Labels" ) labels_doc="$field_doc";;
            esac
        done
        labels_count=$(echo "$labels_doc" | jq .labels.nodes | jq length)
        labels_str=""
        for (( j=0; j<labels_count; j++ )) ; do
            label=$(echo "$labels_doc" | jq -r .labels.nodes[$j].name)
            labels+=(label)
            if [[ "$label" == "epic" ]]; then
                has_epic_label=true
            fi
            if [[ -z "$labels_str" ]]; then
                labels_str="$label"
            else
                labels_str="$labels_str,$label"
            fi
        done

        if ! [[ $estimate == null ]]; then
          ((total_sp+=estimate))
        fi

        echo "$url" >> "$cur_folder/issues.txt"

        echo "\"$status\" \"$epic\" \"$type\" $estimate \"$labels_str\"" \
            >> "$cur_folder/predemo.txt"
        echo "* [$title]($url)" >> "$cur_folder/predemo.txt"
        echo "" >> "$cur_folder/predemo.txt"
    done

    if ! [[ $has_next_page == true ]]; then
        break
    fi
done
echo -ne "\n"

if (( $processed_count != $total_count )); then
    error "Failed to fetch: processed $processed_count of $total_count"
fi

echo $total_sp > "$cur_folder/total_sp.txt"
echo "# ${total_sp}sp закрыто (в прошлый раз было ${old_sp}sp)" \
    >> "$cur_folder/predemo.txt"

echo "# Suggesting https://dillinger.io/ for conversion of markdown to gdoc" \
    >> "$cur_folder/predemo.txt"

if kate --version &>/dev/null; then
    kate -b "$cur_folder/predemo.txt" &>/dev/null
elif gedit --version &>/dev/null; then
    gedit -s "$cur_folder/predemo.txt" &>/dev/null
else
    vi "$cur_folder/predemo.txt"
fi

#Check doesn't have labels teamC, *sp
#Check OnReview and Done
