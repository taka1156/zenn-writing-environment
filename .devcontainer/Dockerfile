FROM node:24-alpine

WORKDIR /workspace

ENV LANG=ja_JP.UTF-8 \
    LANGUAGE=ja_JP:ja \
    LC_ALL=ja_JP.UTF-8 \
  TZ=Asia/Tokyo

RUN <<-EOF
apk add --no-cache \
  bash \
  bash-completion \
  ca-certificates \
  tzdata \
  git \
  git-lfs \
  vim \
  curl \
  musl-locales \
  musl-locales-lang
EOF

RUN git lfs install

RUN <<-EOF
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
echo "Asia/Tokyo" > /etc/timezone
EOF

RUN <<-EOF
curl -o ~/.git-prompt.sh https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh
curl -o ~/.git-completion.sh https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash

echo "[ -f ~/.git-prompt.sh ] && source ~/.git-prompt.sh" >> ~/.bashrc
echo "[ -f ~/.git-completion.sh ] && source ~/.git-completion.sh" >> ~/.bashrc
echo "GIT_PS1_SHOWDIRTYSTATE=true" >> ~/.bashrc
echo "GIT_PS1_SHOWUNTRACKEDFILES=true" >> ~/.bashrc
echo "GIT_PS1_SHOWUPSTREAM=auto"  >> ~/.bashrc
git config --system --add safe.directory /workspace
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[01;33m\] \w \[\033[01;31m\]\$(__git_ps1 \"(%s)\") \\n+\[\033[01;34m\]\\$ \[\033[00m\]"' >> ~/.bashrc
EOF

RUN yarn global add zenn-cli \
        markdownlint-cli \
        markdownlint \
        @textlint/textlint-plugin-markdown \
        textlint \
        textlint-rule-preset-ja-technical-writing \
        textlint-rule-ja-no-mixed-period \
        textlint-rule-no-dropping-the-ra \
        textlint-rule-no-doubled-joshi \
        textlint-rule-spellcheck-tech-word

CMD ["bash"]
