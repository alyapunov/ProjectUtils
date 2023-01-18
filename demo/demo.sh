#!/bin/bash
# BSD 2-Clause License
#
# Copyright (c) 2022, Aleksandr Lyapunov
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

org="tarantool"
token=""
login=$USER
token_file=~/.token
since=""
finalize=false

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
longopts="login:,token:,token_file:,since:,help,finalize"

opts=$(getopt --options "$shortopts" --long "$longopts" --name "$0" -- "$@")
eval set -- "$opts"

while true; do
    case "$1" in
        -l | --login ) login=$2; shift 2;;
        -t | --token ) token=$2; shift 2;;
        -f | --token_file ) token_file=$2; shift 2;;
        -s | --since ) since=$2; shift 2;;
        -h | --help ) usage; shift 1;;
        --finalize ) finalize=true; shift 1;;
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

old_folder=$(date -d "$since" +./%Y-%m-%d)
cur_folder=$(date +./%Y-%m-%d)

if [[ $finalize == false ]]; then

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

cat > "$cur_folder/predemo.txt" <<- EndOfMessage
# Это предемо. В принципе его уже можно скопировать в слайды.
# Для копирования markdown в google docs подойдет https://dillinger.io/.
# Также опционально можно попробовать сгенерировать финальное демо.
# Прямо сейчас скрипт скорее всего ждет того, что этот файл отредактируют,
# в любом случае финальный шаг можно повторить, передав скрипту ключ --finalize.
#
# Финальный шаг скрипта читает построчно этот файл, генерируюя новый файл с
# финальным демо.
# Все строки, начинающиеся с #, пропускаются (кроме строчки про закрытые sp).
# Пустые строки тоже пропускаются.
# Строки, начинающиеся с ! рассматриваются как шаблон.
# В шаблоне должны быть слова и/или фразы, помеченные символом &.
# Чтобы отметить слово, достаточно написать & перед ним (без пробела), чтобы
# отметить фразу, надо обернуть ее в конструкцию &(...).
# Скрипт найдет в шаблоне помеченные таким образом слова/фразы и заменит
# их на markdown ссылки, которые будет искать в файле после этой строки шаблона.
# Результат будет выведен в финальный файл, в виде markdown строчки списка.
# Также есть специальный шаблон "!МелочиN" (N - цифра), который подставит один
# из предопределенных шаблонов с N ссылками.
# Все остальные строки исходного файла будут переданы в финальный без изменений.
# Если не удалось распарсить пометку слова/фразы или не удалось найти нужное
# количество ссылок - оно напечатает ошибку и прекратит работу.
#
# Пример подготовленного файла:
# # this comment will be ignored
# !Закрыт &тикет и &(другой тикет), которые были сложны.
# This phrase is omitted by link searcher.
# * [Title1](https://github.com/issues/1)
# * [Title2](https://github.com/issues/2)
# Some other phrase.
# * [Title3](https://github.com/issues/3)
#
# Пример результата:
# * Закрыт [тикет](https://github.com/issues/1) и [другой тикет](https://github.com/issues/2), которые были сложны.
# Some other phrase.
# * [Title3](https://github.com/issues/3)
################################################################################

EndOfMessage

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

        echo "# \"$status\" \"$epic\" \"$type\" $estimate \"$labels_str\"" \
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

if kate --version &>/dev/null; then
    kate -b "$cur_folder/predemo.txt" &>/dev/null
elif gedit --version &>/dev/null; then
    gedit -s "$cur_folder/predemo.txt" &>/dev/null
elif vi --version &>/dev/null; then
    vi "$cur_folder/predemo.txt"
else
    echo "No editor was found! Only predemo was generated."
    echo "Here it is $cur_folder/predemo.txt"
    echo "You may edit it as it is described in it and run final stage:"
    echo "$0 <...> --finalize"
    exit 1
fi

fi # if [[ $finalize == false ]]

if ! [[ -f "$cur_folder/predemo.txt" ]]; then
    error "Required file '$cur_folder/predemo.txt' was not found"
fi

pre_lines=()
sp_line=
while IFS= read -r line; do
    pattern="^# ([0-9]*)sp закрыто"
    if [[ "$line" =~ $pattern ]]; then
        sp_line="$line"
        continue
    fi
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    if [[ "$line" =~ ^[[:space:]]*$ ]]; then
        continue
    fi
    pre_lines+=("$line")
done < "$cur_folder/predemo.txt"

cat > "$cur_folder/demo.txt" <<- EndOfMessage
# Для копирования markdown в google docs подойдет https://dillinger.io/.
# (сейчас нужно будет шрифт поменять (17) и междустрочный интервал (1.5))
################################################################################

EndOfMessage

pregen=()
pregen+=("Ничего")
pregen+=("Прочая &мелочь")
pregen+=("&Пара &мелочей")
pregen+=("&Несколько &прочих &мелочей")
pregen+=("&Несколько &разных &прочих &мелочей")
pregen+=("&Несколько &мелочей &разной &степени &важности")
pregen+=("&Целый &выводок &разных &небольших &багофиксов и &исправлений")
pregen+=("&Целый &выводок &разных &прочих &небольших &багофиксов и &исправлений")
pregen+=("&Огромная &масса &небольших &багофиксов и &исправлений &разной &степени &важности")
pregen+=("&Огромная &масса &небольших &багофиксов и &исправлений &разной &степени &сложности и &важности")

function subst_count {
    orig_line="$1"
    line="$1 "
    counter=0
    pattern='^([^&]*)&(.*)$'
    pattern_check_none='^[,.;[:space:]].*$'
    pattern_check_phrase='^\(.*$'
    pattern_word='^([^,.;[:space:]]*)([,.;[:space:]].*)$'
    pattern_phrase='^\(([^\)]+)\)(.*)$'
    prefix=""
    while [[ "$line" =~ $pattern ]]; do
        left="${BASH_REMATCH[1]}"
        right="${BASH_REMATCH[2]}"
        if [[ "$right" =~ $pattern_check_none ]]; then
            prefix="$prefix$left$"
            line="$right"
            continue
        fi

        if [[ "$right" =~ $pattern_check_phrase ]]; then
            if ! [[ "$right" =~ $pattern_phrase ]]; then
                error "Unterminated parentheses sequence: $orig_line"
            fi
        elif ! [[ "$right" =~ $pattern_word ]]; then
            error "Fatal error during word match: $orig_line"
        fi
        name="${BASH_REMATCH[1]}"
        prefix=""
        line="${BASH_REMATCH[2]}"
        ((counter++))
    done
    echo $counter
}

function subst_do {
    orig_line="$1"
    line="$1 "
    res=""
    counter=2
    pattern='^([^&]*)&(.*)$'
    pattern_check_none='^[,.;[:space:]].*$'
    pattern_check_phrase='^\(.*$'
    pattern_word='^([^,.;[:space:]]*)([,.;[:space:]].*)$'
    pattern_phrase='^\(([^\)]+)\)(.*)$'
    prefix=""
    while [[ "$line" =~ $pattern ]]; do
        left="${BASH_REMATCH[1]}"
        right="${BASH_REMATCH[2]}"
        if [[ "$right" =~ $pattern_check_none ]]; then
            prefix="$prefix$left&"
            line="$right"
            continue
        fi

        if [[ "$right" =~ $pattern_check_phrase ]]; then
            if ! [[ "$right" =~ $pattern_phrase ]]; then
                error "Unterminated parentheses sequence: $orig_line"
            fi
        elif ! [[ "$right" =~ $pattern_word ]]; then
            error "Fatal error during word match: $orig_line"
        fi
        prefix="$prefix$left"
        name="${BASH_REMATCH[1]}"
        line="${BASH_REMATCH[2]}"
        res="$res$prefix[$name](${!counter})"
        prefix=""
        ((counter++))
    done
    res="$res$prefix$line"
    echo $res
}

lines_count="${#pre_lines[@]}"
for ((i = 0 ; i < $lines_count ; i++)); do
    line="${pre_lines[$i]}"
    if ! [[ "$line" =~ ^!(.*)$ ]]; then
        echo "$line" >> "$cur_folder/demo.txt"
        continue
    fi
    orig_template="${BASH_REMATCH[1]}"
    template="$orig_template"
    if [[ "$template" =~ ^Мелочи([0-9])$ ]]; then
        template="${pregen[${BASH_REMATCH[1]}]}"
    fi

    need_urls=$(subst_count "$template")
    if [[ -z "$need_urls" ]]; then
        error "Failed to parse template"
    fi

    ((found_urls = 0))
    urls=()
    for ((  ; i + 1 < lines_count && found_urls < need_urls ; i++ )); do
        url_line="${pre_lines[$i + 1]}"
        if [[ "$url_line" =~ ^!(.*)$ ]]; then
            break
        fi

        hpattern='^[^h]*h(.*)$'
        while [[ "$url_line" =~ $hpattern ]]; do
            url_line="${BASH_REMATCH[1]}"
            url_pattern='^(ttps?://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|])(.*)$'
            if [[ "$url_line" =~ $url_pattern ]]; then
                ((++found_urls))
                urls+=("h${BASH_REMATCH[1]}")
                url_line="${BASH_REMATCH[2]}"
            fi
        done
    done

    if (( found_urls != need_urls )); then
        error "Failed to substitute template '$orig_template':" \
            "found $found_urls urls while needed $need_urls."
    fi

    substituted=$(subst_do "$template" "${urls[@]}")
    if [[ -z "substituted" ]]; then
        error "Fatal error in template substitution"
    fi

    echo "* $substituted" >> "$cur_folder/demo.txt"
done

echo "$sp_line" >> "$cur_folder/demo.txt"

if kate --version &>/dev/null; then
    kate "$cur_folder/demo.txt" &>/dev/null
elif gedit --version &>/dev/null; then
    gedit "$cur_folder/demo.txt" &>/dev/null
elif vi --version &>/dev/null; then
    vi "$cur_folder/demo.txt"
else
    echo "No editor was found!"
    echo "Here is your demo file $cur_folder/demo.txt"
    exit 0
fi

#Check doesn't have labels teamC, *sp
#Check OnReview and Done
